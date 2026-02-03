# Per-ARN summary (one row per resource with tag count)
aws resourcegroupstaggingapi get-resources \
  --region us-east-1 \
  --query 'ResourceTagMappingList[]' \
  --output json \
| jq -r --arg acct "$(aws sts get-caller-identity --query Account --output text)" '
    .[] as $i
    | [
        $acct,
        "us-east-1",
        $i.ResourceARN,
        ($i.ResourceARN | split(":"))[2],   # Service
        (($i.Tags // []) | length)          # TagCount
      ] | @csv
  ' | (echo "AccountId,Region,ResourceARN,Service,TagCount" && cat) \
  > all_resources_us-east-1.csv

# Flattened tags (one row per tag key/value per resource)
aws resourcegroupstaggingapi get-resources \
  --region us-east-1 \
  --query 'ResourceTagMappingList[]' \
  --output json \
| jq -r --arg acct "$(aws sts get-caller-identity --query Account --output text)" '
    .[] as $i
    | ($i.Tags // [])[]
    | [
        $acct,
        "us-east-1",
        $i.ResourceARN,
        ($i.ResourceARN | split(":"))[2],
        .Key, .Value
      ] | @csv
  ' | (echo "AccountId,Region,ResourceARN,Service,TagKey,TagValue" && cat) \
  > all_resources_tags_us-east-1.csv