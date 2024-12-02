#!/bin/bash

set -Eeuo pipefail

function get_fs_of_directory {
    [ -z "$1" ] || [ ! -d "$1" ] && return
    echo -n "$(stat -c %T -f "$1")"
}

function check_current_cgroup {
    # determining if the system is running cgroupv1 or cgroupv2
    # using systemd approach as in
    # https://github.com/systemd/systemd/blob/d6d450074ff7729d43476804e0e19c049c03141d/src/basic/cgroup-util.c#L2105-L2149

    CGROUP_ID="cgroupfs"
    CGROUP2_ID="cgroup2fs"
    TMPFS_ID="tmpfs"

    cgroup_dir_fs="$(get_fs_of_directory /sys/fs/cgroup)"

    if [[ "$cgroup_dir_fs" == "$CGROUP2_ID" ]]; then
        echo "v2"
        return
    elif [[ "$cgroup_dir_fs" == "$TMPFS_ID" ]]; then
        if [[ "$(get_fs_of_directory /sys/fs/cgroup/unified)" == "$CGROUP2_ID" ]]; then
            echo "v1 (cgroupv2systemd)"
            return
        fi
        if [[ "$(get_fs_of_directory /sys/fs/cgroup/systemd)" == "$CGROUP2_ID" ]]; then
            echo "v1 (cgroupv2systemd232)"
            return
        fi
        if [[ "$(get_fs_of_directory /sys/fs/cgroup/systemd)" == "$CGROUP_ID" ]]; then
            echo "v1"
            return
        fi
    fi
    # if we came this far despite all those returns, it means something went wrong
    echo "failed to determine cgroup version for this system" >&2
    exit 1
}

function check_running_containerd_tasks {
    containerd_runtime_status_dir=/run/containerd/io.containerd.runtime.v2.task/k8s.io

    # if the status dir for k8s.io namespace does not exist, there are no containers
    # in said namespace
    if [ ! -d $containerd_runtime_status_dir ]; then
        echo "$containerd_runtime_status_dir does not exists - no tasks in k8s.io namespace" 
        return 0
    fi

    # count the number of containerd tasks in the k8s.io namespace
    num_tasks=$(ls -1 /run/containerd/io.containerd.runtime.v2.task/k8s.io/ | wc -l)

    if [ "$num_tasks" -eq 0 ]; then
        echo "no active tasks in k8s.io namespace" 
        return 0
    fi

    echo "there are $num_tasks active tasks in the k8s.io containerd namespace - terminating"
    return 1
}