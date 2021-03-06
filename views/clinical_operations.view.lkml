view: clinical_operations {
  # Or, you could make this view a derived table, like this:
  derived_table: {
    sql:
      WITH visit_cap_sent_by_cc AS (
        SELECT e.encounter_uuid AS encounter_uuid,
          coalesce(nullif(trim(initcap(concat(u.first_name, ' ', u.last_name))), ''), 'Unknown Users') AS user_name,
          rank() over (partition by e.encounter_uuid order by aud.data ->> 'timestamp' desc) as pos
        FROM encounter_details AS e
        LEFT JOIN audit_trail AS aud ON (aud."data"->>'object_uuid')::uuid = e.encounter_uuid
        LEFT JOIN users u ON u.email = aud.data ->>'username'
        WHERE e.initial_visit_summary_sent is not null AND (
          aud. "data" -> 'changes' -> 'initial_visit_summary_sent' -> 'new_value' IS NOT NULL OR
          aud. "data"->'changes'->>'root[''initial_visit_summary_sent'']' IS NOT NULL
        )
      ),
      result_cap_sent_by_cc AS (
        SELECT e.encounter_uuid as encounter_uuid,
         coalesce(nullif(trim(initcap(concat(u.first_name, ' ', u.last_name))), ''), 'Unknown Users') AS user_name,
         rank() over (partition by e.encounter_uuid order by aud.data ->> 'timestamp' desc) as pos
        FROM encounter_details AS e
        LEFT JOIN audit_trail AS aud ON (aud."data" ->> 'object_uuid')::uuid = e.encounter_uuid
        LEFT JOIN users u ON u.email = aud.data ->>'username'
        WHERE e.cap_sent_to_patient IS NOT NULL AND (
          aud. "data" -> 'changes' -> 'cap_sent_to_patient' -> 'new_value' IS NOT NULL OR
          aud. "data"->'changes'->>'root[''cap_sent_to_patient'']' IS NOT NULL
        )
      ),
      total_and_cc_order_sent_by_cc AS (
        SELECT encounter_uuid, user_name, pos, count(*) AS order_count
        FROM (
          SELECT e.encounter_uuid AS encounter_uuid,
           coalesce(nullif(trim(initcap(concat(u.first_name, ' ', u.last_name))), ''), 'Unknown Users') AS user_name,
           rank() over (partition by gto.id order by gtoh.created_at desc) as pos
          FROM encounter_details AS e
          LEFT JOIN gene_test_orders AS gto ON e.encounter_uuid=gto.encounter_uuid
          LEFT JOIN gene_test_orders_history AS gtoh ON gto.id=gtoh.gene_test_orders_id
          LEFT JOIN users AS u ON gtoh.user_uuid = u.uuid
          WHERE e.encounter_type in ('visit', 'cc-intake', 'group-session') AND
            gtoh.order_status ='sent_to_lab'
        ) AS encounter_orders
        GROUP BY encounter_uuid, user_name, pos
      ),
      pa_forms_sent_by_cc AS (
        SELECT e.encounter_uuid AS encounter_uuid,
          coalesce(nullif(trim(initcap(concat(u.first_name, ' ', u.last_name))), ''), 'Unknown Users') AS user_name,
          rank() over (partition by pa.id order by pah.created_at desc) as pos
        FROM encounter_details AS e
        LEFT JOIN preauthorizations AS pa ON pa.encounter_uuid=e.encounter_uuid
        LEFT JOIN preauthorizations_history AS pah ON pa.id=pah.preauthorizations_id
        LEFT JOIN users AS u ON pah.user_uuid = u.uuid
        WHERE e.encounter_type in ('visit', 'cc-intake', 'group-session') AND
          pa.dispatch_status='pa_form_sent' AND
          pah.dispatch_status ='pa_form_sent'
      ),
      cc_metrics AS (
        SELECT e.encounter_uuid AS encounter_uuid,
          v.user_name AS visit_cap_cc_user_name,
          r.user_name AS result_cap_cc_user_name,
          t.user_name AS total_and_cc_order_cc_user_name,
          p.user_name AS pa_forms_cc_user_name
        FROM encounter_details AS e
        LEFT JOIN visit_cap_sent_by_cc v ON v.encounter_uuid = e.encounter_uuid AND v.pos = 1
        LEFT JOIN result_cap_sent_by_cc r ON r.encounter_uuid = e.encounter_uuid AND r.pos = 1
        LEFT JOIN total_and_cc_order_sent_by_cc t ON t.encounter_uuid = e.encounter_uuid  AND t.pos = 1
        LEFT JOIN pa_forms_sent_by_cc p ON p.encounter_uuid = e.encounter_uuid AND p.pos = 1
      ),
      high_priority_patients AS (
        SELECT DISTINCT p.patient_uuid AS puuid
        FROM audit_trail at
        JOIN patient_encounter_summary p ON at.data ->> 'object_uuid' = p.patient_uuid::text
        WHERE
            at.data ->> 'object' = 'Patients'
            AND at.data ->> 'service_type' = 'edit'
            AND at.data -> 'changes' -> 'high_priority' ->> 'new_value' = 'true'
            AND at.data -> 'changes' -> 'high_priority' ->> 'old_value' = 'false'
      ),
      order_info AS (
        SELECT e.encounter_uuid AS encounter_uuid,
          CASE WHEN e.encounter_type ='lab_test_authorization' THEN e.date_received_report ELSE max(gto.date_received_report) END AS date_received_report
        FROM encounter_details as e
        LEFT JOIN gene_test_orders AS gto ON  e.encounter_uuid = gto.encounter_uuid
        WHERE
            e.encounter_type in ('visit', 'group-session', 'cc-intake', 'lab_test_authorization') AND
            e.followup_cap_completed_date is not null AND
            ((e.encounter_type = 'lab_test_authorization' and e.date_received_report IS NOT NULL) OR
              (e.encounter_type != 'lab_test_authorization' and gto.date_received_report IS NOT NULL))
        GROUP BY e.encounter_uuid, e.encounter_type, e.date_received_report
      ),
      final AS (
        SELECT
          coalesce(initcap(pes.patient_first_name), '') || ' ' || coalesce(initcap(pes.patient_last_name), '') AS patient_name,
          pes.patient_dob AS patient_dob,
          pes.patient_email AS patient_email,
          coalesce(initcap(pes.external_patient_id), '') AS external_patient_id,
          pes.patient_uuid AS patient_uuid,
          pes.patient_state::text AS patient_state,
          prt.data ->> 'display_name' AS referral_program,
          po.name AS referral_partner,
          rc.data ->> 'name'AS referral_channel,
          CASE
            WHEN ed.encounter_type = 'scp' AND ed.encounter_subtype = 'partner_initiated/pre_test' THEN 'tro'
            WHEN ed.encounter_type = 'scp' AND ed.encounter_subtype != 'partner_initiated/pre_test' THEN 'scp'
            ELSE ed.encounter_type
          END AS encounter_type,
          ed.encounter_uuid AS encounter_uuid,
          ed.created_at AS created_at,
          ed.date_of_service AS date_of_service,
          ed.initial_visit_summary_sent AS initial_visit_summary_sent,
          ed.initial_cap_completed_date AS initial_cap_completed_date,
          ed.cap_sent_to_patient AS cap_sent_to_patient,
          ed.followup_cap_completed_date AS followup_cap_completed_date,
          ed.user_uuid AS user_uuid,
          ed.date_test_ordered AS date_test_ordered,
          ed.ror_visit_status AS ror_visit_status,
          ed.ror_date_contacted AS ror_date_contacted,
          ed.order_status AS order_status,
          ed.visit_status AS visit_status,
          INITCAP(REPLACE(ed.visit_provider, '_', ' ')) AS visit_provider,
          ed.date_test_recommended AS date_test_recommended,
          ed.test_recommended AS test_recommended,
          oi.date_received_report AS date_received_report,
          cm.visit_cap_cc_user_name AS visit_cap_cc_user_name,
          cm.result_cap_cc_user_name AS result_cap_cc_user_name,
          cm.total_and_cc_order_cc_user_name AS total_and_cc_order_cc_user_name,
          cm.pa_forms_cc_user_name AS pa_forms_cc_user_name,
          CASE WHEN hpp.puuid IS NULL THEN false ELSE true END AS is_high_priority_patient
        FROM encounter_details ed
        LEFT JOIN patient_encounter_summary pes ON ed.user_uuid = pes.patient_uuid
        LEFT JOIN high_priority_patients hpp ON hpp.puuid = ed.user_uuid
        LEFT JOIN order_info oi ON oi.encounter_uuid = ed.encounter_uuid
        LEFT JOIN cc_metrics AS cm ON cm.encounter_uuid = ed.encounter_uuid
        LEFT JOIN partners AS prt ON ed.partner_uuid = prt.uuid
        LEFT JOIN referral_channels AS rc ON prt.data ->> 'referral_channel_id' = rc.data ->> 'id'
        LEFT JOIN
        (
          SELECT p.data->'id' AS "id", array_to_string(array_agg(po.name), ', ') AS "name"
          FROM partners p
          JOIN partner_organizations po ON (p.data->'partner_organization_ids')::jsonb @> po.id::text::jsonb
          GROUP BY p.data->'id'
        ) AS po ON prt.data->'id' = po.id
        WHERE (pes.is_deleted is NULL OR pes.is_deleted = false)
      )
      SELECT * from final ;;
  }

  # Define your dimensions and measures here, like this:


  dimension: patient_state {
    map_layer_name: us_states
    description: "Patient State"
    type: string
    sql: ${TABLE}.patient_state ;;
  }

  dimension: referral_program {
    description: "Referral Program"
    type: string
    sql: ${TABLE}.referral_program ;;
  }

  dimension: referral_partner {
    description: "Referral Partner"
    type: string
    sql: ${TABLE}.referral_partner ;;
  }

  dimension: referral_channel {
    description: "Referral Channel"
    type: string
    sql: ${TABLE}.referral_channel ;;
  }

  dimension: encounter_type {
    description: "Encounter Type"
    type: string
    sql: ${TABLE}.encounter_type ;;
  }

  dimension: encounter_uuid {
    description: "Encounter UUID"
    type: string
    primary_key: yes
    sql: ${TABLE}.encounter_uuid ;;
  }

  dimension: patient_name {
    description: "Patient Name"
    type: string
    sql: ${TABLE}.patient_name ;;
  }

  dimension: patient_email {
    description: "Patient Email"
    type: string
    sql: ${TABLE}.patient_email ;;
  }

  dimension: external_patient_id {
    description: "External Patient Id"
    type: string
    sql: ${TABLE}.external_patient_id ;;
  }

  dimension_group: patient_dob {
    description: "Patient Date of Birth"
    type: time
    drill_fields: [encounter_type, referral_program]
    timeframes: [
      raw,
      time,
      date,
      day_of_week,
      week_of_year,
      week,
      month,
      month_name,
      quarter,
      year
    ]
    sql: ${TABLE}."patient_dob" ;;
  }

  dimension_group: created_at {
    description: "Encounter Creation Date (UTC)"
    type: time
    drill_fields: [encounter_type, referral_program]
    timeframes: [
      raw,
      time,
      date,
      day_of_week,
      week_of_year,
      week,
      month,
      month_name,
      quarter,
      year
    ]
    sql: ${TABLE}."created_at" ;;
  }

  dimension_group: date_of_service {
    description: "Encounter Date of Service (UTC)"
    type: time
    drill_fields: [encounter_type, referral_program]
    timeframes: [
      raw,
      time,
      date,
      day_of_week,
      week_of_year,
      week,
      month,
      month_name,
      quarter,
      year
    ]
    sql: ${TABLE}."date_of_service" ;;
  }

  dimension_group: initial_visit_summary_sent {
    description: "Initial Visit Summary Sent Date (UTC)"
    type: time
    drill_fields: [encounter_type, referral_program]
    timeframes: [
      raw,
      time,
      date,
      day_of_week,
      week_of_year,
      week,
      month,
      month_name,
      quarter,
      year
    ]
    sql: ${TABLE}."initial_visit_summary_sent" ;;
  }

  dimension_group: initial_cap_completed_date {
    description: "Initial CAP Completed Date (UTC)"
    type: time
    drill_fields: [encounter_type, referral_program]
    timeframes: [
      raw,
      time,
      date,
      day_of_week,
      week_of_year,
      week,
      month,
      month_name,
      quarter,
      year
    ]
    sql: ${TABLE}."initial_cap_completed_date" ;;
  }

  dimension_group: cap_sent_to_patient {
    description: "CAP Sent to Patient Date (UTC)"
    type: time
    drill_fields: [encounter_type, referral_program]
    timeframes: [
      raw,
      time,
      date,
      day_of_week,
      week_of_year,
      week,
      month,
      month_name,
      quarter,
      year
    ]
    sql: ${TABLE}."cap_sent_to_patient" ;;
  }

  dimension_group: followup_cap_completed_date {
    description: "Followup CAP Completed Date (UTC)"
    type: time
    drill_fields: [encounter_type, referral_program]
    timeframes: [
      raw,
      time,
      date,
      day_of_week,
      week_of_year,
      week,
      month,
      month_name,
      quarter,
      year
    ]
    sql: ${TABLE}."followup_cap_completed_date" ;;
  }

  dimension: user_uuid {
    description: "Patient UUID"
    type: string
    sql: ${TABLE}.user_uuid ;;
  }

  dimension_group: date_test_ordered {
    description: "Date Test Ordered (UTC)"
    type: time
    hidden: yes
    drill_fields: [encounter_type, referral_program]
    timeframes: [
      raw,
      time,
      date,
      day_of_week,
      week_of_year,
      week,
      month,
      month_name,
      quarter,
      year
    ]
    sql: ${TABLE}."date_test_ordered" ;;
  }

  dimension: ror_visit_status {
    description: "RoR Visit Status"
    type: string
    sql: ${TABLE}.ror_visit_status ;;
  }

  dimension_group: ror_date_contacted {
    description: "RoR Date Contacted (UTC)"
    type: time
    drill_fields: [encounter_type, referral_program]
    timeframes: [
      raw,
      time,
      date,
      day_of_week,
      week_of_year,
      week,
      month,
      month_name,
      quarter,
      year
    ]
    sql: ${TABLE}."ror_date_contacted" ;;
  }

  dimension_group: date_received_report {
    description: "Date Received Report (UTC)"
    type: time
    drill_fields: [encounter_type, referral_program]
    timeframes: [
      raw,
      time,
      date,
      day_of_week,
      week_of_year,
      week,
      month,
      month_name,
      quarter,
      year
    ]
    sql: ${TABLE}."date_received_report" ;;
  }

  dimension: order_status {
    description: "Order Status"
    type: string
    sql: ${TABLE}.order_status ;;
  }

  dimension: visit_status {
    description: "Visit Status"
    type: string
    sql: ${TABLE}.visit_status ;;
  }

  dimension: visit_provider {
    description: "Visit Provider"
    type: string
    sql: ${TABLE}.visit_provider ;;
  }

  dimension_group: date_test_recommended {
    description: "Date Test Recommended (UTC)"
    type: time
    drill_fields: [encounter_type, referral_program]
    timeframes: [
      raw,
      time,
      date,
      day_of_week,
      week_of_year,
      week,
      month,
      month_name,
      quarter,
      year
    ]
    sql: ${TABLE}."date_test_recommended" ;;
  }

  dimension: test_recommended {
    description: "Was Testing Recommended"
    type: string
    sql: ${TABLE}.test_recommended ;;
  }

  dimension: is_high_priority_patient {
    description: "Is High-priority Patient"
    type: yesno
    sql: ${TABLE}.is_high_priority_patient ;;
  }
  # cm.visit_cap_cc_user_name AS visit_cap_cc_user_name,
  # cm.result_cap_cc_user_name AS result_cap_cc_user_name,
  # cm.total_and_cc_order_cc_user_name AS total_and_cc_order_cc_user_name,
  # cm.pa_forms_cc_user_name AS pa_forms_cc_user_name

  dimension: visit_cap_cc_user_name {
    description: "Visit CAP Sending CC"
    type: string
    sql: ${TABLE}.visit_cap_cc_user_name ;;
  }

  dimension: result_cap_cc_user_name {
    description: "Result CAP Sending CC"
    type: string
    sql: ${TABLE}.result_cap_cc_user_name ;;
  }

  dimension: total_and_cc_order_cc_user_name {
    description: "Total and Order Sending CC"
    type: string
    sql: ${TABLE}.total_and_cc_order_cc_user_name ;;
  }

  dimension: pa_forms_cc_user_name {
    description: "PA Forms Sending CC"
    type: string
    sql: ${TABLE}.pa_forms_cc_user_name ;;
  }

  dimension: visit_cap_completion_time {
    type: number
    label: "Visit CAP completion time (visit encounters) from date of visit"
    sql: count_business_days(${date_of_service_date}, ${initial_cap_completed_date_date}) ;;
  }

  dimension: visit_cap_release_time {
    type: number
    label: "Visit CAP Release time (visit encounters) from CAP completion date"
    sql: count_business_days(${initial_cap_completed_date_date}, ${initial_visit_summary_sent_date}) ;;
  }

  dimension: result_cap_completed_time {
    type: number
    label: "Results CAP completion time from date report was received"
    sql: count_business_days(${date_received_report_date}, ${followup_cap_completed_date_date}) ;;
  }

  dimension: result_cap_release_time {
    type: number
    label: "Results CAP Release time from CAP completion date"
    sql: count_business_days(${followup_cap_completed_date_date}, ${cap_sent_to_patient_date}) ;;
  }

  dimension: order_request_update_time {
    type: number
    label: "Order-request update time from date of visit"
    sql: count_business_days(${date_of_service_date}, ${date_test_recommended_date}) ;;
  }

  # TODO
  dimension: order_placement_time {
    type: number
    label: "Test order placement time from date visit CAP Completed (DO NOT USE)"
    sql: count_business_days(${date_of_service_date}, ${date_test_recommended_date}) ;;
  }

  dimension: pa_form_sent_time {
    type: number
    label: "PA form submission time"
    sql:
      SELECT count_business_days(pa.dispatch_date, MIN(pah.created_at))
      FROM ${TABLE} AS te
      JOIN preauthorizations AS pa ON te.encounter_uuid = pa.encounter_uuid
      JOIN preauthorizations_history AS pah ON  pah.preauthorizations_id = pa.id
      WHERE te.encounter_type in ('visit', 'cc-intake', 'group-session') and
          pa.dispatch_status = 'pa_form_sent' AND
          pah.dispatch_status = 'waiting_to_submit' AND pah.dispatch_reason = 'awaiting_cc_submission'
      GROUP BY pa.id, pa.dispatch_date;;
  }

  measure: count {
    type: count
  }

  measure: average_visit_completion_time_in_days {
    type: average
    label: "Average visit CAP completion time from date of visit"
    filters: [visit_cap_completion_time: ">=0"]
    sql: ${visit_cap_completion_time} ;;
    drill_fields: [visit_provider, average_visit_completion_time_in_days]
    value_format_name: decimal_2
  }

  measure: average_result_cap_completed_time_in_days {
    type: average
    label: "Average results CAP completion time from date report was received"
    filters: [result_cap_completed_time: ">=0"]
    sql: ${result_cap_completed_time} ;;
    drill_fields: [visit_provider, average_result_cap_completed_time_in_days]
    value_format_name: decimal_2
  }

  measure: average_order_request_update_time_in_days {
    type: average
    label: "Average order-request update time from date of visit"
    filters: [order_request_update_time: ">=0"]
    sql: ${order_request_update_time} ;;
    drill_fields: [visit_provider, average_order_request_update_time_in_days]
    value_format_name: decimal_2
  }

  measure: count_visit_caps {
    type: count
    label: "Total number of visit CAPs sent by CCs"
    filters: [visit_cap_cc_user_name: "-NULL"]
    drill_fields: [visit_cap_cc_user_name,patient_name]
  }

  measure: count_result_caps {
    type: count
    label: "Total number of result CAPs sent by CCs"
    filters: [result_cap_cc_user_name: "-NULL"]
    drill_fields: [result_cap_cc_user_name]
  }

  measure: count_orders_sent {
    type: count
    label: "Total number of orders sent by CCs"
    filters: [total_and_cc_order_cc_user_name: "-NULL"]
    drill_fields: [total_and_cc_order_cc_user_name]
  }

  measure: count_pa_forms_sent {
    type: count
    label: "Total number of PA forms sent by CCs"
    filters: [pa_forms_cc_user_name: "-NULL"]
    drill_fields: [pa_forms_cc_user_name]
  }

  measure: average_visit_cap_release_time_in_days {
    type: average
    label: "Average visit CAP Release time (visit encounters) from CAP completion date"
    filters: [visit_cap_release_time: ">=0"]
    sql: ${visit_cap_completion_time} ;;
    drill_fields: [visit_cap_cc_user_name, average_visit_cap_release_time_in_days]
    value_format_name: decimal_2
  }

  measure: average_result_cap_release_time_in_days {
    type: average
    label: "Average results CAP Release time from CAP completion date"
    filters: [result_cap_release_time: ">=0"]
    sql: ${visit_cap_completion_time} ;;
    drill_fields: [result_cap_cc_user_name, average_result_cap_release_time_in_days]
    value_format_name: decimal_2
  }

  measure: average_order_placement_time_in_days {
    type: average
    label: "Average test order placement time from date visit CAP completed"
    filters: [order_placement_time: ">=0"]
    sql: ${order_placement_time} ;;
    drill_fields: [total_and_cc_order_cc_user_name, average_order_placement_time_in_days]
    value_format_name: decimal_2
  }

  measure: average_pa_form_sent_time_in_days {
    type: average
    label: "Average PA form submission time"
    filters: [pa_form_sent_time: ">=0"]
    sql: ${pa_form_sent_time} ;;
    drill_fields: [pa_forms_cc_user_name, average_pa_form_sent_time_in_days]
    value_format_name: decimal_2
  }
}
