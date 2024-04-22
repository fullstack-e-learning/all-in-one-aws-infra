# allinone-aws-infra

This Infrastructure contain :

- ec2
- efs
- rds (postgres)
- elb (application)

debug:

Terraform
```sh
# .tf File format check 
terraform fmt -check
# validate
terraform validate
# Plan
terraform plan
# apply
terraform apply --auto-approve
# destroy
terraform destroy --auto-approve
```

ansible
```sh
# ansible module to parse terrform state file for dynamic inventory
ansible-galaxy collection install cloud.terraform
# overview inventory
ansible-inventory -i ansible/inventory.yml --list --vars
# playbook
ansible-playbook -i ansible/inventory.yml ansible/playbook.yml -e application_version=1.0.13 
```