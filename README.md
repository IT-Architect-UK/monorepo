# build-logs

Deploy logs are pushed to this branch by
`automation/ansible/playbooks/provision-vm.yml` (the "Ship deploy log" task)
as `logs/<os_label>/<timestamp>-<vm_name>.log`.

This is an orphan branch: it shares no history with `main` and holds nothing
but these logs. Do not merge it.
