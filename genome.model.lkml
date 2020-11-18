connection: "qa_analytics_db"

include: "/views/*.view.lkml"

# explore: patient_encounter_summary {
#   join: encounter_details {
#     type: left_outer
#     sql_on: ${patient_encounter_summary.patient_uuid} = ${encounter_details.user_uuid} ;;
#     relationship: one_to_many
#   }
# }

explore: encounter_details {
  access_filter: {
    field: patient_encounter_summary.referral_program
    user_attribute: referral_program
  }
  join: patient_encounter_summary {
    type: left_outer
    sql_on: ${patient_encounter_summary.patient_uuid} = ${encounter_details.user_uuid} ;;
    relationship: many_to_one
  }
  join: partners {
    type: left_outer
    sql_on: ${patient_encounter_summary.partner_id} = ${partners.id} ;;
    relationship: many_to_one
  }
  join: referral_channels {
    type: left_outer
    sql_on: ${partners.referral_channel_id} = ${referral_channels.id} ;;
    relationship: many_to_one
  }
  join: high_priority_patients {
    type: left_outer
    sql_on: ${patient_encounter_summary.patient_uuid} = ${high_priority_patients.high_prio_patient_uuid} ;;
    relationship: one_to_one
    }
  join: top_referral_programs {
    type: left_outer
    sql_on: ${patient_encounter_summary.referral_program} = ${top_referral_programs.referral_program} ;;
    relationship: many_to_one
  }
}
