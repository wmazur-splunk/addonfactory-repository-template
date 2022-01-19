#!/usr/bin/env bash

REPOORG=splunk

echo "Setting branch protection rules for" "$REPOORG"/"$REPO"

create_pattern="mutation createBranchProtectionRule {
    createBranchProtectionRule(input: {
        repositoryId: \""%s"\"
        pattern: \""%s"\"
        "%s"
    })
    {
        branchProtectionRule {
            repository { nameWithOwner }
            pattern
            creator { login }
            matchingRefs(last:100) { edges { node { name } } }
            branchProtectionRuleConflicts(last:10)  { edges { node { conflictingBranchProtectionRule { pattern } } } }
            requiresApprovingReviews
            requiredApprovingReviewCount
            dismissesStaleReviews
            requiresCodeOwnerReviews
            restrictsReviewDismissals
            reviewDismissalAllowances(first:1) { nodes { actor { __typename ... on Team { name } } } }
            requiresStatusChecks
            requiresStrictStatusChecks
            requiredStatusCheckContexts
            requiresConversationResolution
            requiresCommitSignatures
            requiresLinearHistory
            isAdminEnforced
            allowsForcePushes
            allowsDeletions
        }
    }
}"

update_pattern="${create_pattern/repositoryId/branchProtectionRuleId}"
update_pattern="${update_pattern//createBranchProtectionRule/updateBranchProtectionRule}"

main_settings="requiresApprovingReviews: true
    requiredApprovingReviewCount: 2
    dismissesStaleReviews: true
    requiresCodeOwnerReviews: false
    restrictsReviewDismissals: true
    reviewDismissalActorIds: [
          \""$ADMIN_TEAM_ID"\"
    ]
    requiresStatusChecks: true
    requiresStrictStatusChecks: true
    requiredStatusCheckContexts: [
        \"call-workflow / pre-publish\"
    ]
    requiresConversationResolution: false
    requiresCommitSignatures: true
    requiresLinearHistory: false
    isAdminEnforced: false
    restrictsPushes: false
    allowsForcePushes: false
    allowsDeletions: false"

develop_settings="${main_settings/allowsDeletions: false/allowsDeletions: true}"
develop_settings="${develop_settings/allowsForcePushes: false/allowsForcePushes: true}"

common_settings="requiresApprovingReviews: false
    requiresStatusChecks: false
    requiresConversationResolution: false
    requiresLinearHistory: false
    isAdminEnforced: false
    requiresCommitSignatures: true
    restrictsPushes: false
    allowsDeletions: true
    allowsForcePushes: true"

repo_id="$(gh api "/repos/$REPOORG/$REPO" -q .node_id)"

look_for_branch_protection_rules_template="query {
    repository(owner:\"${REPOORG}\", name:\"$REPO\") {
        branchProtectionRules(first:%s) {
            nodes { id pattern }
            totalCount
        }
    }
}"

bpr_to_get=20
look_for_branch_protection_rules=$(printf "$look_for_branch_protection_rules_template" "$bpr_to_get")
branch_protection_rules=$(gh api graphql -F "query=$look_for_branch_protection_rules")
number_of_bpr=$(echo $branch_protection_rules | jq '.[] | .repository.branchProtectionRules.totalCount')

if (( $number_of_bpr > $bpr_to_get ))
then
  look_for_branch_protection_rules=$(printf "$look_for_branch_protection_rules_template" "$number_of_bpr")
  branch_protection_rules=$(gh api graphql -F "query=$look_for_branch_protection_rules")
fi

declare -A branches=( ["main"]="main" ["develop"]="develop" ["common"]="**/**")
declare -a rule_names=("main" "develop" "common")

for rule_name in "${rule_names[@]}"
do
    rule_id=$(echo $branch_protection_rules | jq -r ".[] | .repository.branchProtectionRules.nodes | .[] |  select(.pattern == \""${branches[$rule_name]}"\" )| .id")
    pattern_name="${rule_name}_settings"

    if [ -z $rule_id ]
    then
      echo "no rule for ${rule_name} branch"
      query=$(printf "$create_pattern" "$repo_id" "${branches[$rule_name]}" "${!pattern_name}")
    else
      echo "rule exists for ${rule_name} branch"
      query=$(printf "$update_pattern" "$rule_id" "${branches[$rule_name]}" "${!pattern_name}")
    fi

    gh api graphql -F "query=$query"
done

configure_security_analysis () {
    gh api -X PUT repos/$REPOORG/$REPO/vulnerability-alerts || true
    gh api -X PUT repos/$REPOORG/$REPO/automated-security-fixes || true
}

configure_security_analysis

