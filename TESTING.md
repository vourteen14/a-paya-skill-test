# Testing Guide - Elasticsearch AWS

## Compliance Check vs Requirements

| # | Requirement | Status | Notes |
|---|-------------|--------|-------|
| 1a | Brings up an AWS instance | Done | 3x t2.micro EC2 across 3 AZs |
| 1b | Elasticsearch with credentials + encrypted comms | Done | xpack.security + TLS on :9200 & :9300 |
| 1c | Demonstrates it is functioning | Done | `verify.yml` playbook + curl commands in README |
| 2a | Description of solution and choices | Done | README "Answers to Exercise Questions" |
| 2b | Resources consulted | Done | README "Resources Consulted" section |
| 2c | Time spent + feedback | Done | README "Time Spent & Feedback" section |
| 3 | Must use AWS free tier | Done | t2.micro, 30GB EBS, public subnets (no NAT) |
| 4 | Elasticsearch access and communication must be secure | Done | SG + TLS + auth + EBS encryption |
| BONUS | Cluster of 3 Elasticsearch nodes | Done | `cluster_size = 3`, multi-AZ, mutual TLS |

All 7 exercise questions answered in README.

## Prerequisites Checklist

Before running any test, verify all of these:

```bash
# 1. Terraform (or OpenTofu) >= 1.3
terraform version   # or: tofu version

# 2. Ansible >= 2.14
ansible --version

# 3. AWS CLI >= 2.x, credentials configured
aws sts get-caller-identity   # must return your account ID

# 4. Ansible collection
ansible-galaxy collection install cloud.terraform
# or inside terraform-ansible/:
ansible-galaxy collection install -r requirements.yml

# 5. curl
curl --version
```

## Testing Steps

### Step 1 - Set Your IP

```bash
MY_IP=$(curl -s ifconfig.me)
echo "Your IP: $MY_IP"
```

### Step 2 - Review / Override Passwords

Edit `terraform-ansible/roles/elasticsearch/defaults/main.yml`:
```yaml
elastic_password: "YourStrongPassword123!"   # change this
kibana_password:  "AnotherStrongOne456!"     # change this
```

Set matching environment variables:
```bash
export TF_VAR_elastic_password="YourStrongPassword123!"
export TF_VAR_management_cidr="${MY_IP}/32"
```

### Step 3 - Initialize and Deploy

```bash
cd terraform-ansible

terraform init

terraform plan \
  -var="management_cidr=${MY_IP}/32" \
  -var="elastic_password=YourStrongPassword123!"

# Terraform provisions AWS AND runs all 4 Ansible playbooks automatically
terraform apply \
  -var="management_cidr=${MY_IP}/32" \
  -var="elastic_password=YourStrongPassword123!"
```

Expected duration: ~15-20 minutes total
- EC2 provisioning: ~3-5 min
- Ansible playbook 01 (primary bootstrap): ~5-7 min
- Ansible playbook 02 (secondary nodes): ~5-7 min
- Ansible playbook 03 (auth): ~1 min
- Ansible playbook 04 (validation): ~1 min

### Step 4 - Get Outputs

```bash
terraform output
# public_ips        = ["54.x.x.1", "54.x.x.2", "54.x.x.3"]
# elasticsearch_url = "https://54.x.x.1:9200"
# ssh_command       = "ssh -i ssh_key.pem ec2-user@54.x.x.1"
```

## Verification Test Cases

Replace `NODE_IP` and `PASSWORD` with values from Terraform output.

### Test 1 - Cluster Health (Green + 3 nodes)

```bash
curl -k -u elastic:PASSWORD \
  https://NODE_IP:9200/_cluster/health?pretty
```

Expected:
```json
{
  "cluster_name" : "elasticsearch",
  "status" : "green",
  "number_of_nodes" : 3,
  "number_of_data_nodes" : 3,
  "active_primary_shards" : ...,
  "unassigned_shards" : 0
}
```

Fail if: `status` is `red` or `yellow`, or `number_of_nodes` != 3.

### Test 2 - Authentication Enforced (401 without credentials)

```bash
curl -k -o /dev/null -w "%{http_code}" https://NODE_IP:9200/
```

Expected: `401`

Fail if: returns `200` (auth bypass).

### Test 3 - Plain HTTP Rejected

```bash
curl -v http://NODE_IP:9200/ 2>&1 | grep -E "Empty reply|Connection refused|curl: \(1\)"
```

Expected: connection fails or empty reply. Plain HTTP must not work.

Fail if: returns any JSON response over HTTP.

### Test 4 - HTTPS Works with Credentials

```bash
curl -k -u elastic:PASSWORD https://NODE_IP:9200/
```

Expected: JSON with `"tagline" : "You Know, for Search"`

### Test 5 - All Nodes Listed

```bash
curl -k -u elastic:PASSWORD https://NODE_IP:9200/_cat/nodes?v
```

Expected: 3 rows, each with an IP address and role `dim` (data+ingest+master).

### Test 6 - Index and Retrieve a Document

```bash
# Write
curl -k -u elastic:PASSWORD \
  -X PUT https://NODE_IP:9200/test/_doc/1 \
  -H 'Content-Type: application/json' \
  -d '{"message": "hello world", "timestamp": "2026-06-11"}'

# Read back
curl -k -u elastic:PASSWORD https://NODE_IP:9200/test/_doc/1
```

Expected write response: `"result":"created"` or `"result":"updated"`

Expected read response:
```json
{
  "_index" : "test",
  "_id" : "1",
  "_source" : { "message" : "hello world", ... }
}
```

### Test 7 - Inter-node TLS (Transport Layer)

```bash
# SSH into primary node
ssh -i terraform-ansible/ssh_key.pem ec2-user@NODE_IP

# On the node, check transport SSL is active
sudo grep -E "transport.ssl|http.ssl" /etc/elasticsearch/elasticsearch.yml
```

Expected:
```
xpack.security.transport.ssl.enabled: true
xpack.security.http.ssl.enabled: true
```

### Test 8 - EBS Encryption at Rest

```bash
aws ec2 describe-volumes \
  --filters "Name=tag:Name,Values=elasticsearch*" \
  --query "Volumes[*].{ID:VolumeId,Encrypted:Encrypted}" \
  --region ap-southeast-1
```

Expected: all volumes show `"Encrypted": true`

### Test 9 - Security Group Restrictions

```bash
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=elasticsearch*" \
  --query "SecurityGroups[*].IpPermissions[*].{Port:FromPort,CIDR:IpRanges[*].CidrIp}" \
  --region ap-southeast-1
```

Expected: ports 22 and 9200 are restricted to `YOUR_IP/32`, not `0.0.0.0/0`. Port 9300 should be restricted to `10.0.0.0/16` (VPC only).

## Teardown

```bash
cd terraform-ansible
terraform destroy \
  -var="management_cidr=${MY_IP}/32" \
  -var="elastic_password=YourStrongPassword123!"
```

Verify in AWS Console that all EC2 instances, VPC, subnets, and security groups are removed.

