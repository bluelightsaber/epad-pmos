#!/bin/sh
# Uso: cg2.sh "controladores" (vacío = ninguno)  — crea/borra cgroups en bucle
mkdir -p /sys/fs/cgroup; mount -t cgroup2 cgroup2 /sys/fs/cgroup 2>/dev/null
echo "<3>cg2: disponibles $(cat /sys/fs/cgroup/cgroup.controllers); usar: $1" > /dev/kmsg
for c in $1; do echo "+$c" > /sys/fs/cgroup/cgroup.subtree_control || echo "<3>cg2: no +$c" > /dev/kmsg; done
i=0
while [ $i -lt 3000 ]; do
  mkdir -p /sys/fs/cgroup/a$i/b
  sh -c "echo \$\$ > /sys/fs/cgroup/a$i/b/cgroup.procs; cat /proc/self/cgroup >/dev/null"
  rmdir /sys/fs/cgroup/a$i/b /sys/fs/cgroup/a$i
  [ $((i % 500)) = 0 ] && echo "<3>cg2 $i" > /dev/kmsg
  i=$((i+1))
done
echo "<3>cg2 fin" > /dev/kmsg
