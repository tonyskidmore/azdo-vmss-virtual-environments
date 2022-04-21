#!/bin/bash

# This is mainly used to highlight that we can use cloud-init as part of the deployment process if needed.
# the below output can be viewed in the Azure Portal under the VMSS - Instances and then viewing
# Boot diagnostics - Serial log

echo "***** cat /etc/sudoers"
cat /etc/sudoers

echo "***** cat /etc/environment"
cat /etc/environment

# See custom-data.sh.bak in this same directory as described in https://www.skidmore.co.uk/post/2022_04_20_azure_devops_vmss_agents_part2/
