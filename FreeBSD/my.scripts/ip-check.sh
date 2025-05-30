#!/bin/sh
# ip-check.sh - Optimized network scanning with nmap/ping fallback
# Compatible with FreeBSD /bin/sh

# Show usage
usage() {
    cat << EOF
Usage: $(basename "$0") -n network/mask [-a|-o] [-p] [-m] [-t timeout] [-j jobs]

Options:
    -n network/mask  Network to scan (e.g., 192.168.1.0/24)
    -a              Show only alive/responding hosts (default)
    -o              Show only down/non-responding hosts
    -p              Force ping mode (use when nmap unavailable or for speed)
    -m              Show MAC addresses for alive hosts (local network only)
    -t timeout      Host timeout in seconds (default: 2)
    -j jobs         Number of parallel jobs for ping mode (default: 50)
    -h              Show this help message

Examples:
    $(basename "$0") -n 192.168.1.0/24 -a -m
    $(basename "$0") -n 10.0.0.0/16 -o -p -j 100
    $(basename "$0") -n 172.16.0.0/24 -t 1

Note: nmap is preferred as it can detect hosts behind firewalls.
      Ping mode is faster but may miss firewalled hosts.
      MAC addresses only visible for hosts on local network.
EOF
    exit ${1:-0}
}

# Default values
MODE="alive"
TIMEOUT="2"
PARALLEL="50"
NETWORK=""
USE_PING="no"
SHOW_MAC="no"

# Parse arguments using getopt (FreeBSD compatible)
args=$(getopt aopmn:t:j:h $*)
if [ $? -ne 0 ]; then
    usage 1
fi

set -- $args
while [ $# -gt 0 ]; do
    case "$1" in
        -a)
            MODE="alive"
            shift
            ;;
        -o)
            MODE="down"
            shift
            ;;
        -p)
            USE_PING="yes"
            shift
            ;;
        -m)
            SHOW_MAC="yes"
            shift
            ;;
        -n)
            NETWORK="$2"
            shift 2
            ;;
        -t)
            TIMEOUT="$2"
            shift 2
            ;;
        -j)
            PARALLEL="$2"
            shift 2
            ;;
        -h)
            usage 0
            ;;
        --)
            shift
            break
            ;;
        *)
            usage 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$NETWORK" ]; then
    echo "Error: Network parameter -n is required" >&2
    usage 1
fi

# Validate network format
validate_network() {
    echo "$1" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$'
    if [ $? -ne 0 ]; then
        echo "Error: Invalid network format. Use x.x.x.x/mask" >&2
        return 1
    fi
    
    # Extract IP and mask
    ip=$(echo "$1" | cut -d/ -f1)
    mask=$(echo "$1" | cut -d/ -f2)
    
    # Validate IP octets
    IFS='.' read -r o1 o2 o3 o4 << EOF
$ip
EOF
    
    if [ "$o1" -gt 255 ] || [ "$o2" -gt 255 ] || [ "$o3" -gt 255 ] || [ "$o4" -gt 255 ]; then
        echo "Error: Invalid IP address" >&2
        return 1
    fi
    
    # Validate mask
    if [ "$mask" -gt 32 ] || [ "$mask" -lt 8 ]; then
        echo "Error: Invalid network mask (must be 8-32)" >&2
        return 1
    fi
    
    return 0
}

# Check for nmap
check_nmap() {
    NMAP=$(which nmap 2>/dev/null) || NMAP=""
    if [ -z "$NMAP" ] || [ ! -x "$NMAP" ]; then
        return 1
    fi
    return 0
}

# Expand CIDR to IP range
expand_cidr() {
    network="$1"
    base_ip=$(echo "$network" | cut -d/ -f1)
    mask=$(echo "$network" | cut -d/ -f2)
    
    # Convert IP to decimal
    IFS='.' read -r o1 o2 o3 o4 << EOF
$base_ip
EOF
    ip_dec=$(( (o1 << 24) + (o2 << 16) + (o3 << 8) + o4 ))
    
    # Calculate network and broadcast
    # Using bc for power calculation since sh doesn't have **
    host_bits=$((32 - mask))
    num_hosts=$(echo "2^$host_bits" | bc)
    network_dec=$((ip_dec & ((0xFFFFFFFF << host_bits) & 0xFFFFFFFF)))
    broadcast_dec=$((network_dec + num_hosts - 1))
    
    # Generate IP list
    current=$((network_dec + 1))
    last=$((broadcast_dec - 1))
    
    while [ "$current" -le "$last" ]; do
        # Convert decimal back to IP
        o1=$(( (current >> 24) & 255 ))
        o2=$(( (current >> 16) & 255 ))
        o3=$(( (current >> 8) & 255 ))
        o4=$(( current & 255 ))
        echo "$o1.$o2.$o3.$o4"
        current=$((current + 1))
    done
}

# Ping scan a single host
ping_host() {
    ip="$1"
    timeout="$2"
    
    if ping -c 1 -W "$timeout" "$ip" >/dev/null 2>&1; then
        echo "$ip UP"
    else
        echo "$ip DOWN"
    fi
}

# Parallel ping scan
ping_scan() {
    network="$1"
    mode="$2"
    timeout="$3"
    parallel="$4"
    
    # Create temporary directory for job control
    tmpdir=$(mktemp -d /tmp/scanner.XXXXXX)
    trap "rm -rf $tmpdir" EXIT INT TERM
    
    # Generate IP list and scan
    expand_cidr "$network" > "$tmpdir/iplist"
    
    # Split IP list for parallel processing
    total_ips=$(wc -l < "$tmpdir/iplist" | tr -d ' ')
    if [ "$total_ips" -eq 0 ]; then
        return
    fi
    
    # Process in batches
    batch_size=$(( (total_ips + parallel - 1) / parallel ))
    if [ "$batch_size" -eq 0 ]; then
        batch_size=1
    fi
    
    split -l "$batch_size" "$tmpdir/iplist" "$tmpdir/batch_"
    
    # Run ping scans in background
    for batch in "$tmpdir"/batch_*; do
        (
            while read -r ip; do
                ping_host "$ip" "$timeout"
            done < "$batch"
        ) > "$batch.out" &
    done
    
    # Wait for all jobs
    wait
    
    # Collect and filter results
    cat "$tmpdir"/*.out 2>/dev/null | \
    if [ "$mode" = "alive" ]; then
        grep "UP$" | awk '{print $1}'
    else
        grep "DOWN$" | awk '{print $1}'
    fi | \
    sort -t"." -k1,1n -k2,2n -k3,3n -k4,4n
}

# Optimized nmap scan
nmap_scan() {
    network="$1"
    mode="$2"
    timeout="$3"
    parallel="$4"
    
    # Build nmap options for optimal performance
    nmap_opts="-n"                          # No DNS resolution
    nmap_opts="$nmap_opts -v"               # Verbose (reports all hosts)
    nmap_opts="$nmap_opts -sn"              # Ping scan
    nmap_opts="$nmap_opts -T4"              # Aggressive timing
    nmap_opts="$nmap_opts --max-retries 1"  # Reduce retries
    nmap_opts="$nmap_opts --host-timeout ${timeout}s"
    nmap_opts="$nmap_opts --min-parallelism $parallel"
    
    # For alive hosts with MAC addresses, we need different output format
    if [ "$mode" = "alive" ] && [ "$SHOW_MAC" = "yes" ]; then
        # Create temporary file for results
        tmpfile=$(mktemp /tmp/ip-check.XXXXXX)
        trap "rm -f $tmpfile" EXIT INT TERM
        
        # Use normal output format to get MAC addresses
        # First, just get the nmap output to a temp file
        $NMAP $nmap_opts "$network" 2>/dev/null > "${tmpfile}.raw"
        
        # Parse it with a simpler approach
        awk '
        /Nmap scan report for/ {
            if (ip && is_up) print ip, "|", mac
            ip = $NF
            mac = ""
            is_up = 0
        }
        /Host is up/ {
            is_up = 1
        }
        /MAC Address:/ {
            mac = $3
            for(i=4; i<=NF; i++) mac = mac" "$i
        }
        END {
            if (ip && is_up) print ip, "|", mac
        }
        ' "${tmpfile}.raw" > "$tmpfile"
        
        rm -f "${tmpfile}.raw"
        
        # For IPs without MAC in nmap output, try ARP cache
        while IFS='|' read -r ip mac; do
            # Trim whitespace
            ip=$(echo "$ip" | sed 's/^ *//;s/ *$//')
            mac=$(echo "$mac" | sed 's/^ *//;s/ *$//')
            
            if [ -z "$mac" ]; then
                # Try to get MAC from ARP cache (FreeBSD format)
                arp_line=$(arp -a | grep "($ip)")
                if [ -n "$arp_line" ]; then
                    arp_mac=$(echo "$arp_line" | awk '{print $4}')
                    if [ -n "$arp_mac" ] && [ "$arp_mac" != "incomplete" ] && [ "$arp_mac" != "(incomplete)" ]; then
                        # Just convert to uppercase - FreeBSD arp already uses colons
                        mac=$(echo "$arp_mac" | tr 'a-f' 'A-F')
                        # Add ARP cache indicator
                        mac="$mac (ARP cache)"
                    fi
                fi
            fi
            
            if [ -n "$mac" ]; then
                printf "%-15s  %s\n" "$ip" "$mac"
            else
                printf "%-15s\n" "$ip"
            fi
        done < "$tmpfile" | sort -t"." -k1,1n -k2,2n -k3,3n -k4,4n
        
        rm -f "$tmpfile"
    else
        # Use grepable output for simple IP listing
        nmap_opts="$nmap_opts -oG -"
        
        # Set grep pattern based on mode
        if [ "$mode" = "alive" ]; then
            pattern="Up"
        else
            pattern="Down"
        fi
        
        # Run scan and filter results with single command
        $NMAP $nmap_opts "$network" 2>/dev/null | \
        awk "/${pattern}\$/{print \$2}" | \
        sort -t"." -k1,1n -k2,2n -k3,3n -k4,4n
    fi
}

# Calculate number of hosts in network
calculate_hosts() {
    mask=$(echo "$1" | cut -d/ -f2)
    # Use bc for power calculation
    hosts=$(echo "2^(32-$mask)-2" | bc)
    echo "$hosts"
}

# Main execution
main() {
    # Validate network format
    validate_network "$NETWORK" || exit 1
    
    # Determine scan method
    if [ "$USE_PING" = "no" ]; then
        if check_nmap; then
            SCAN_METHOD="nmap"
        else
            echo "Warning: nmap not found, falling back to ping mode"
            echo "Note: ping may miss hosts behind firewalls"
            echo ""
            USE_PING="yes"
            SCAN_METHOD="ping"
        fi
    else
        SCAN_METHOD="ping"
    fi
    
    # Calculate network size
    num_hosts=$(calculate_hosts "$NETWORK")
    
    # Display scan configuration
    echo "Network scanner configuration:"
    echo "  Network: $NETWORK (~$num_hosts hosts)"
    echo "  Mode: Show $MODE hosts"
    echo "  Method: $SCAN_METHOD"
    if [ "$SHOW_MAC" = "yes" ] && [ "$MODE" = "alive" ]; then
        echo "  MAC addresses: yes (local network only)"
    fi
    echo "  Timeout: ${TIMEOUT}s per host"
    if [ "$SCAN_METHOD" = "ping" ]; then
        echo "  Parallel jobs: $PARALLEL"
    else
        echo "  Parallelism: $PARALLEL concurrent probes"
    fi
    echo ""
    
    # Warning for large networks
    if [ "$num_hosts" -gt 10000 ]; then
        echo "Warning: Large network detected. This may take several minutes."
        echo "Consider using a smaller timeout (-t 1) or higher parallelism (-j 100)"
        if [ "$SCAN_METHOD" = "nmap" ]; then
            echo "Or use ping mode (-p) for faster but less accurate results"
        fi
        echo ""
    fi
    
    # MAC address compatibility check
    if [ "$SHOW_MAC" = "yes" ]; then
        if [ "$MODE" = "down" ]; then
            echo "Note: MAC addresses not available for down hosts"
            SHOW_MAC="no"
        elif [ "$SCAN_METHOD" = "ping" ]; then
            echo "Note: MAC addresses not available in ping mode"
            SHOW_MAC="no"
        fi
    fi
    
    # Perform scan
    echo "Scanning..."
    start_time=$(date +%s)
    
    if [ "$SCAN_METHOD" = "ping" ]; then
        result=$(ping_scan "$NETWORK" "$MODE" "$TIMEOUT" "$PARALLEL")
    else
        result=$(nmap_scan "$NETWORK" "$MODE" "$TIMEOUT" "$PARALLEL")
    fi
    
    end_time=$(date +%s)
    elapsed=$((end_time - start_time))
    
    # Display results
    if [ -n "$result" ]; then
        echo ""
        if [ "$MODE" = "alive" ] && [ "$SHOW_MAC" = "yes" ]; then
            echo "Hosts $MODE:"
            printf "%-15s  %s\n" "IP Address" "MAC Address"
            printf "%-15s  %s\n" "--------------" "-------------------------------------------"
        else
            echo "Hosts $MODE:"
        fi
        echo "$result"
        count=$(echo "$result" | wc -l | tr -d ' ')
        echo ""
        echo "Found $count hosts in ${elapsed}s"
    else
        echo ""
        echo "No $MODE hosts found in ${elapsed}s"
    fi
}

# Run main function
main
