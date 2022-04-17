#!/bin/bash

# https://github.com/microsoft/azure-pipelines-agent/issues/3546

echo "running as: $(whoami)"
echo "running shell: $(readlink /proc/$$/exe)"

# run Post-generation scripts
# https://github.com/actions/virtual-environments/blob/main/docs/create-image-and-azure-resources.md#post-generation-scripts
find /opt/post-generation -mindepth 1 -maxdepth 1 -type f -name "*.sh" -exec bash {} \;

# wait for the Azure DevOps agent Agent.Listener process to start
timeout 15m bash -c 'until pidof Agent.Listener; do echo "Waiting for Agent.Listener" && sleep 5; done'

if pidof Agent.Listener > /dev/null
then
  agent_pid=$(pidof Agent.Listener)
  printf "killing Agent.Listener process: %s\n" "$agent_pid"
  kill "$agent_pid"
else
  echo "Agent.Listener process not found"
fi

sleep 5

# get path information from /etc/environment
pathFromEnv=$(cut -d= -f2 /etc/environment | tail -1)
printf "pathFromEnv:\n %s\n" "$pathFromEnv"

# update /etc/sudoers secure_path
sed -i.bak "/secure_path/d" /etc/sudoers
echo "Defaults secure_path=$pathFromEnv" >> /etc/sudoers
# debug
cat /etc/sudoers

# update agent path files
echo "$pathFromEnv > /agent.path"
echo "$pathFromEnv" > /agent/.path

# get array values for Azure DevOps agent processes
# mapfile -t runPID < <(pgrep -f 'run.sh$')
# mapfile -t agentPID < <(pgrep -f 'bin/Agent.Listener run$')

# echo "runPID: ${runPID[*]}"
# echo "agentPID: ${agentPID[*]}"
# echo "pidof run.sh: $(pidof -x run.sh)"
# echo "pidof Agent.Listener: $(pidof Agent.Listener)"
# echo "pgrep run.sh: $(pgrep -f 'run.sh')"
# echo "pgrep Agent.Listener: $(pgrep -f 'Agent.Listener')"

# agent_pid=$(pgrep -f 'Agent.Listener')
# run_pid=$(pgrep -f 'run.sh')

# TODO: do we actually need to worry about killing existing processes?
# TODO: is there a race condition between walinuxagent and cloud-init?
# https://github.com/Azure/WALinuxAgent/issues/1938#issuecomment-657293920
# kill the Agent.Listener process
# if [[ "${#agentPID[*]}" -eq 1 ]] && [[ -n "${agentPID[0]}" ]]
# if [[ -n "$run_pid" ]]
# then
#   printf "killing run_pid: %s\n" "$run_pid"
#   kill "$run_pid"
# else
#   echo "run.sh process not found"
# fi

# kill the run.sh process
# if [[ "${#runPID[*]}" -eq 1 ]] && [[ -n "${runPID[0]}" ]]
# if [[ -n "$agent_pid" ]]
# then
#   printf "killing bin/Agent.Listener: %s\n" "$agent_pid"
#   kill "$(pidof Agent.Listener)"
# else
#   printf "bin/Agent.Listener process not found"
# fi

# agent_pid=$(pidof Agent.Listener) && kill --verbose "$agent_pid" || echo "Agent.Listener process not found"

# echo "pgrep run.sh: $(pgrep -f 'run.sh')"
# echo "pgrep Agent.Listener: $(pgrep -f 'Agent.Listener')"

# finally restart the Azure DevOps agent after the path updates
echo "running: sudo -E runuser AzDevOps -c '/bin/sh /agent/run.sh"
echo "sudo -E runuser AzDevOps -c '/bin/bash /agent/run.sh'" | at now

# https://github.com/simonasaitta/agent-pool-scripts/blob/main/enableagent.sh
# log_message "Starting agent"
# sudo -E nice -n 0 runuser AzDevOps -c "/bin/bash $dir/run.sh $runArgs" > /dev/null 2>&1 &
# disown