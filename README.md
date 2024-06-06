# all-in-one-aws-infra

This repo contain `Infrastructure as code` , `Configuration as code` , `CI & CD` pipeline for [all-in-one](https://github.com/fullstack-e-learning/all-in-one).
- In the CI/CD pipeline , It will create the necessary `aws` Infrastructure like more then one `ec2`, `efs` for file share across application, an `postgres db` and `elb` for loadbalancing.
- Once the Infra is created, the ansible pipeline will Kick in and Intall the necessary tools need to run the application
- Along with this, It will set the applicaion as Unix service and run it. 

More details ? navigate through the code.

### This Infrastructure contain :

- ec2
- efs
- rds (postgres)
- elb (application)

### debug:

#### Terraform
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

#### ansible
```sh
# ansible module to parse terrform state file for dynamic inventory
ansible-galaxy collection install cloud.terraform
# overview inventory
ansible-inventory -i ansible/inventory.yml --list --vars
# playbook
ansible-playbook -i ansible/inventory.yml ansible/playbook.yml -e application_version=1.0.13 
```
