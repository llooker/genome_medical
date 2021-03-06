view: partners {
  sql_table_name: public.partners ;;

  dimension: uuid {
    primary_key: yes
    type: string
    sql: ${TABLE}."uuid" ;;
  }

  dimension: data {
    type: string
    sql: ${TABLE}."data" ;;
  }

  dimension: test {
    type: yesno
    sql: ${TABLE}."test" ;;
  }

  dimension: id {
    type: string
    sql: nullif(jsonb_extract_path(${TABLE}.data, 'id')::text, '')::int ;;
  }

  dimension: name {
    type: string
    sql: jsonb_extract_path(${TABLE}.data, 'name')::text ;;
  }

  dimension: display_name {
    type: string
    sql: jsonb_extract_path(${TABLE}.data, 'display_name')::text ;;
  }

  dimension: partner_organization_ids {
    type: string
    sql: jsonb_extract_path(${TABLE}.data, 'partner_organization_ids')::text ;;
  }

  dimension: referral_channel_id {
    type: string
    sql: jsonb_extract_path(${TABLE}.data, 'referral_channel_id')::text ;;
  }

  dimension: insurance_enabled {
    type: string
    sql: jsonb_extract_path(${TABLE}.data, 'insurance_enabled')::text ;;
  }

  dimension: eligibility_referral_code {
    type: string
    sql: jsonb_extract_path(${TABLE}.data, 'eligibility_referral_code')::text ;;
  }

  dimension: insurance_package_address {
    type: string
    sql: jsonb_extract_path(${TABLE}.data, 'insurance_package_address')::text ;;
  }

  dimension: price_per_webinar_package {
    type: number
    sql: jsonb_extract_path(${TABLE}.data, 'price_per_webinar_package')::number ;;
  }

  dimension: self_registration_enabled {
    type: string
    sql: jsonb_extract_path(${TABLE}.data, 'self_registration_enabled')::text ;;
  }

  dimension: specific_consultations_only {
    type: string
    sql: jsonb_extract_path(${TABLE}.data, 'specific_consultations_only')::text ;;
  }

  dimension: insurance_claim_balance_bill {
    type: string
    sql: jsonb_extract_path(${TABLE}.data, 'insurance_claim_balance_bill')::text ;;
  }

  dimension: referral_api_address_required {
    type: string
    sql: jsonb_extract_path(${TABLE}.data, 'referral_api_address_required')::text ;;
  }

  dimension: allow_patients_register_notify {
    type: string
    sql: jsonb_extract_path(${TABLE}.data, 'allow_patients_register_notify')::text ;;
  }

  dimension: allow_patients_self_scheduling {
    type: string
    sql: jsonb_extract_path(${TABLE}.data, 'allow_patients_self_scheduling')::text ;;
  }

  dimension: send_patient_registration_link {
    type: string
    sql: jsonb_extract_path(${TABLE}.data, 'send_patient_registration_link')::text ;;
  }

  dimension: allow_patients_reminders_notify {
    type: string
    sql: jsonb_extract_path(${TABLE}.data, 'allow_patients_reminders_notify')::text ;;
  }

  dimension: referral_outreach_automation_enabled {
    type: string
    sql: jsonb_extract_path(${TABLE}.data, 'referral_outreach_automation_enabled')::text ;;
  }

  dimension: send_actionability_determination_flag {
    type: string
    sql: jsonb_extract_path(${TABLE}.data, 'send_actionability_determination_flag')::text ;;
  }

  dimension_group: last_modified_patient_reminder_flag_at {
    type: time
    timeframes: [
      raw,
      time,
      date,
      week,
      month,
      quarter,
      year
    ]
    sql: jsonb_extract_path(${TABLE}.data, 'last_modified_patient_reminder_flag_at')::text::date ;;
  }

  dimension: release_result_cap_upon_result_receipt {
    type: string
    sql: jsonb_extract_path(${TABLE}.data, 'release_result_cap_upon_result_receipt')::text ;;
  }

  measure: count {
    type: count
    drill_fields: []
  }
}
