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
  join: top_referral_programs {
    type: left_outer
    sql_on: ${patient_encounter_summary.referral_program} = ${top_referral_programs.referral_program} ;;
    relationship: many_to_one
  }
}
