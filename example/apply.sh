#!/bin/bash
export TFLOG=debug
rm -f nohup.out plugin-proxmox.log
echo yes | nohup terraform apply 2>&1 &
 