#! /bin/bash
set -e -x

#set this env var in order to overwrite global credstash cmd
CREDSTASH_COMMAND=${CREDSTASH_COMMAND-"credstash"}

AWS_REGION='us-east-1'
KEY_PAIR=
PEM_KEY_FILE=


#remove bastion key pair
function remove_ssh_bastion_key(){
  rm -f "$PEM_KEY_FILE"
}

#kill ssh forwarding process
function kill_ssh_forward_pid(){
  echo "Killing ssh forwarding process"
  kill -9 $(ps -ef | grep $KEY_PAIR | grep -v 'grep' | awk {'print $2'}) || echo "No ssh forwarding process to kill"
}

#get bastion host public dns for ssh tunneling
function get_bastion_host_public_ip(){
  echo "Getting bastion host public DNS"
  IA_BASTION_EC2_ID=$(aws ec2 describe-tags --filters "Name=value,Values=LinuxBastion" | jq ".Tags[0].ResourceId" | sed "s/\"//g")
  IA_BASTION_DNS=$(aws ec2 describe-instances --instance-ids $IA_BASTION_EC2_ID | jq ".Reservations[0].Instances[0].PublicDnsName" | sed "s/\"//g")
}

#log environment
function get_environment(){
  ENVIRONMENT=$($CREDSTASH_COMMAND get environment)
  echo "SSH to bastion host: $ENVIRONMENT"
}

#locally ssh to bastion host based on aws profile
function ssh_to_bastion(){
  remove_ssh_bastion_key
  get_environment
  get_bastion_host_public_ip
  get_ssh_bastion_key
  ssh -v -i "$PEM_KEY_FILE" ec2-user@"$IA_BASTION_DNS"
}

#get bastion ssh key pair
function get_ssh_bastion_key(){
  echo "Adding bastion keypair"


  $CREDSTASH_COMMAND get $KEY_PAIR >> "$PEM_KEY_FILE"
  chmod 400 "$PEM_KEY_FILE"
}

function start_bastion() {
  remove_ssh_bastion_key
  get_environment
  get_bastion_host_public_ip
  get_ssh_bastion_key
  ssh -v -i  "$PEM_KEY_FILE" -N -o StrictHostKeyChecking=no -fo ExitOnForwardFailure=yes -L $LOCAL_PORT:$ENDPOINT:$TCP_PORT ec2-user@"$IA_BASTION_DNS"
}

function stop_bastion() {
  kill_ssh_forward_pid
  remove_ssh_bastion_key
}

usage() {
  cat << EOF
  Usage: $0 start [endpoint] [port] [local-port]
  Usage: $0 stop
  Usage: $0 ssh
  Sets up an SSH tunnel through the the bastion host
  to the specified endpoint on port forward-port.
  If local-port is not specified, it defaults to 8000.
  If port is not specified, it defaults to 5432.
  Can also ssh into bastion box for debugging/troubleshooting
  Prefix AWS_DEFAULT_PROFILE=<> to command to switch between environments
  eg AWS_DEFAULT_PROFILE=staging ./tools/bastion.sh ssh
EOF
}

command=$1
ENDPOINT=$2
TCP_PORT=${3-5432}
LOCAL_PORT=${4-8000}


if [ "$command" = "start" ]; then
  start_bastion
elif [ "$command" = "stop" ]; then
  stop_bastion
elif [ "$command" = "ssh" ]; then
  ssh_to_bastion
else
  usage
  exit
fi
