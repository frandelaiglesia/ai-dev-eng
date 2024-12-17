#!/bin/bash
#====================
# Server Optimization Script for AI/ML, Deep Learning, and Compute Workloads
# by Fran De La Iglesia - https://x.com/frandelaiglesia
# Designed for Ubuntu 22.04 LTS
# Designed for a Server with 16 vCPU 64Gb RAM 1Tb SSD with GPU Nvidia A40 in compute mode.
#====================

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "[ERROR] This script must be run as root. Please re-run it using 'sudo' or as the root user." 1>&2
   echo "[HINT] Example: sudo $0" 1>&2
   exit 1
fi

# Logging setup
LOGFILE="/var/log/server_optimization.log"
SUMMARY_FILE="/var/log/server_optimization_summary.log"
echo "====================" > $LOGFILE
echo "[INFO] Server Optimization Script Started at $(date)" | tee -a $LOGFILE
echo "====================" >> $LOGFILE

# Install missing dependencies
function install_dependencies() {
    echo "[INFO] Checking for missing dependencies..." | tee -a $LOGFILE
    DEPENDENCIES=(cpufrequtils numactl)
    for pkg in "${DEPENDENCIES[@]}"; do
        if ! dpkg -l | grep -qw "$pkg"; then
            echo "[INFO] Installing missing package: $pkg..." | tee -a $LOGFILE
            apt-get install -y $pkg >> $LOGFILE 2>&1 || {
                echo "[ERROR] Failed to install $pkg. Exiting." | tee -a $LOGFILE
                exit 1
            }
        else
            echo "[INFO] Dependency $pkg is already installed." | tee -a $LOGFILE
        fi
    done
}

# Backup critical files before making changes
BACKUP_DIR="/var/backups/server_optimization_$(date +%F_%H-%M-%S)"
function manual_backup() {
    echo "[INFO] Performing manual backup..." | tee -a $LOGFILE
    mkdir -p $BACKUP_DIR
    cp /etc/default/grub $BACKUP_DIR/grub.bak && echo "[INFO] GRUB backup successful." | tee -a $LOGFILE
    cp /etc/fstab $BACKUP_DIR/fstab.bak && echo "[INFO] fstab backup successful." | tee -a $LOGFILE
    cp /etc/sysctl.conf $BACKUP_DIR/sysctl.conf.bak && echo "[INFO] sysctl.conf backup successful." | tee -a $LOGFILE
    echo "[INFO] Manual backup completed. Files saved to $BACKUP_DIR." | tee -a $LOGFILE
}

# Function to validate /etc/fstab before applying changes
function validate_fstab() {
    echo "[INFO] Validating /etc/fstab syntax..." | tee -a $LOGFILE
    if findmnt --verify --tab-file /etc/fstab &>> $LOGFILE; then
        echo "[INFO] fstab syntax is valid." | tee -a $LOGFILE
    else
        echo "[ERROR] fstab validation failed. Reverting changes." | tee -a $LOGFILE
        cp /tmp/fstab.backup /etc/fstab
        exit 1
    fi
}

function optimize_cpu() {
    echo "[INFO] Optimizing CPU configuration (Basic)..." | tee -a $LOGFILE
    if command -v cpufreq-set &> /dev/null; then
        cpufreq-set -g performance
        echo "[INFO] CPU governor set to 'performance'." | tee -a $LOGFILE
    else
        echo "[WARNING] cpufreq-set not found. Skipping CPU governor setting." | tee -a $LOGFILE
    fi
    echo "[INFO] Enabling NUMA awareness for optimized memory access." | tee -a $LOGFILE
    numactl --hardware &>> $LOGFILE
    echo "[SUMMARY] CPU optimization completed." | tee -a $SUMMARY_FILE
}

function optimize_memory() {
    echo "[INFO] Optimizing memory usage (Basic)..." | tee -a $LOGFILE
    if sysctl -n vm.swappiness | grep -q '^10$'; then
        echo "[INFO] vm.swappiness is already set to 10." | tee -a $LOGFILE
    else
        echo "vm.swappiness=10" >> /etc/sysctl.conf
        sysctl vm.swappiness=10 | tee -a $LOGFILE
    fi

    if grep -q "vm.nr_hugepages=512" /etc/sysctl.conf; then
        echo "[INFO] HugePages already configured." | tee -a $LOGFILE
    else
        echo "vm.nr_hugepages=512" >> /etc/sysctl.conf
        sysctl vm.nr_hugepages=512 | tee -a $LOGFILE
    fi
    sysctl -p &>> $LOGFILE
    echo "[SUMMARY] Memory optimization completed." | tee -a $SUMMARY_FILE
}

function optimize_disk_io() {
    echo "[INFO] Optimizing disk I/O (Basic)..." | tee -a $LOGFILE
    validate_fstab
    blockdev --setra 2048 /dev/sda
    echo "[INFO] Updating /etc/fstab to include 'noatime' and 'nodiratime'." | tee -a $LOGFILE
    sed -i '/LABEL=cloudimg-rootfs/ {/noatime/! s/ext4/ext4,noatime,nodiratime/}' /etc/fstab
    validate_fstab
    mount -a && echo "[INFO] Disk I/O optimization applied successfully." | tee -a $LOGFILE
    echo "[SUMMARY] Disk I/O optimization completed." | tee -a $SUMMARY_FILE
}

function configure_network() {
    echo "[INFO] Configuring network for low latency..." | tee -a $LOGFILE
    if sysctl -n net.core.somaxconn | grep -q '^4096$'; then
        echo "[INFO] Network parameters already optimized." | tee -a $LOGFILE
    else
        sysctl -w net.core.somaxconn=4096
        sysctl -w net.ipv4.tcp_tw_reuse=1
        sysctl -p &>> $LOGFILE
    fi
    echo "[SUMMARY] Network optimization completed." | tee -a $SUMMARY_FILE
}

function apply_kernel_tuning() {
    echo "[INFO] Applying kernel tuning..." | tee -a $LOGFILE
    if grep -q "fs.file-max=2097152" /etc/sysctl.conf; then
        echo "[INFO] Kernel parameters already configured." | tee -a $LOGFILE
    else
        echo "fs.file-max=2097152" >> /etc/sysctl.conf
        sysctl fs.file-max=2097152 | tee -a $LOGFILE
    fi
    sysctl -p &>> $LOGFILE
    echo "[SUMMARY] Kernel tuning completed." | tee -a $SUMMARY_FILE
}

function optimize_super() {
    echo "[INFO] Confirming: Super-Optimization applies ALL enhancements. Proceed? [Y/N]" | tee -a $LOGFILE
    read -r confirm
    if [[ $confirm != "Y" && $confirm != "y" ]]; then
        echo "[INFO] Super-optimization cancelled by user." | tee -a $LOGFILE
        return
    fi
    optimize_cpu
    optimize_memory
    optimize_disk_io
    configure_network
    apply_kernel_tuning
    echo "[INFO] Super-optimization completed successfully." | tee -a $LOGFILE
}

function restore_backups() {
    echo "[INFO] Restoring previous backups..." | tee -a $LOGFILE
    cp $BACKUP_DIR/grub.bak /etc/default/grub && echo "[INFO] GRUB restored." | tee -a $LOGFILE
    cp $BACKUP_DIR/fstab.bak /etc/fstab && echo "[INFO] fstab restored." | tee -a $LOGFILE
    cp $BACKUP_DIR/sysctl.conf.bak /etc/sysctl.conf && echo "[INFO] sysctl.conf restored." | tee -a $LOGFILE
    echo "[INFO] Backups restored successfully. Reboot recommended." | tee -a $LOGFILE
}

function show_menu() {
    echo "\nOptimization Options:"
    echo "1. Manual Backup (All Critical Files)"
    echo "2. Optimize CPU Configuration (Basic)"
    echo "3. Optimize Memory Usage (Basic)"
    echo "4. Optimize Disk I/O (Basic)"
    echo "5. Configure Network for Low Latency (Basic)"
    echo "6. Apply Kernel Tuning (Basic)"
    echo "7. Apply All Basic Optimizations"
    echo "8. Super-Optimization for AI/ML Workloads"
    echo "9. Restore Previous Backups"
    echo "10. Exit"
    echo -n "\nSelect an option [1-10]: "
}

# Install dependencies first
install_dependencies

while true; do
    show_menu
    read choice
    case $choice in
        1) manual_backup ;;
        2) optimize_cpu ;;
        3) optimize_memory ;;
        4) optimize_disk_io ;;
        5) configure_network ;;
        6) apply_kernel_tuning ;;
        7) optimize_cpu; optimize_memory; optimize_disk_io; configure_network; apply_kernel_tuning; echo "[INFO] Basic optimizations applied successfully." | tee -a $LOGFILE ;;
        8) optimize_super ;;
        9) restore_backups ;;
        10) echo "[INFO] Exiting. Logs saved at $LOGFILE."; exit 0 ;;
        *) echo "[ERROR] Invalid option. Please try again." | tee -a $LOGFILE ;;
    esac
done
