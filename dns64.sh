#!/bin/bash

# 定义DNS64 IPv6地址列表
dns64_addresses=(
    "2a01:4f9:c010:3f02::1"
    "2001:67c:2b0::4"
    "2001:67c:2b0::6"
    "2a09:11c0:f1:bbf0::70"
    "2a01:4f8:c2c:123f::1"
    "2001:67c:27e4:15::6411"
    "2001:67c:27e4::64"
    "2001:67c:27e4:15::64"
    "2001:67c:27e4::60"
    "2a00:1098:2b::1"
    "2a03:7900:2:0:31:3:104:161"
    "2a00:1098:2c::1"
    "2a09:11c0:100::53"
    "2a01:4ff:f0:9876::1"
    "2001:67c:2960::64"
    "2001:67c:2960::6464"
    "2606:4700:4700::6400"
    "2606:4700:4700::64"
    "2001:4860:4860::64"
    "2001:4860:4860::6464"
)

# 要访问的IPv4域名
ipv4_domain="www.nodeseek.com"

# 存储每个DNS64地址的评分
declare -A dns_scores

# 检测IPv6是否可用，使用ping6
function test_ping6() {
    local ip=$1
    if ping6 -c 3 -w 5 "$ip" > /dev/null; then
        echo "$ip 可达"
        return 0  # 可达返回0
    else
        echo "$ip 不可达"
        return 1  # 不可达返回1
    fi
}

# 测试通过IPv6访问IPv4域名
function test_ipv4_access_via_dns64() {
    local ip=$1
    echo "正在测试通过DNS64访问IPv4域名 $ipv4_domain，使用IPv6地址 $ip..."

    # 使用curl来访问IPv4域名
    if curl -s --resolve "$ipv4_domain":80:"$ip" "http://$ipv4_domain" --max-time 5 > /dev/null; then
        echo "成功：可以通过DNS64访问IPv4域名 $ipv4_domain，使用IPv6地址 $ip"
        return 0  # 成功返回0
    else
        echo "失败：无法通过DNS64访问IPv4域名 $ipv4_domain，使用IPv6地址 $ip"
        return 1  # 失败返回1
    fi
}

# 性能测试，获取ping的响应时间
function test_performance() {
    local ip=$1
    echo "正在测试 $ip 的性能..."

    # 使用time命令来测量ping的响应时间，并提取响应时间
    local result=$(ping6 -c 5 -w 5 "$ip" | tail -n 1 | awk -F '/' '{print $5}')

    # 清理结果，去除非数字部分（只保留数字和小数点）
    result=$(echo "$result" | sed 's/[^0-9.]//g')

    # 检查是否获取到了有效的数字
    if [[ -n $result && $result =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo "$ip 的平均响应时间：$result ms"
        if (( $(echo "$result < 100" | bc -l) )); then
            echo "$ip 的响应时间小于100ms"
            return 0
        else
            return 1
        fi
    else
        echo "$ip 的响应时间无法获取"
        return 1
    fi
}

# 收集每个DNS64地址的评分
function collect_scores() {
    local ip=$1

    # 初始化评分
    local score=0

    # 1. 检查IPv6地址是否可达
    test_ping6 "$ip"
    if [ $? -eq 0 ]; then
        score=$((score + 1))  # 可达加分

        # 2. 测试是否能通过DNS64访问IPv4域名
        test_ipv4_access_via_dns64 "$ip"
        if [ $? -eq 0 ]; then
            score=$((score + 2))  # 成功访问IPv4域名加分
        fi

        # 3. 测试性能
        if test_performance "$ip"; then
            score=$((score + 1))  # 响应时间小于100ms加分
        fi
    fi

    dns_scores["$ip"]=$score
}

# 遍历所有DNS64地址进行测试
for ip in "${dns64_addresses[@]}"; do
    collect_scores "$ip"
    echo "--------------------------------------"
done

# 排序并按评分从高到低输出DNS64地址
echo "根据评分排序DNS64地址（从高到坏）："
sorted_ips=$(for ip in "${!dns_scores[@]}"; do
    # 获取 IPv6 地址和评分
    echo "$ip 评分:${dns_scores[$ip]}"
done | sort -k2 -t ':')
echo "$sorted_ips"
echo "--------------------------------------"
# 显示排名前两名的IP
top_two=$(echo "$sorted_ips" | head -n 2)
# 备份原始 /etc/resolv.conf
cp /etc/resolv.conf /etc/resolv.conf.bak
echo "DNS64更新内容：" 
{
echo "$top_two" | while read -r line; do
    ip=$(echo "$line" | awk '{print $1}')  # 提取每行的第一个字段（即IPv6地址）
    echo "nameserver $ip"  # 更新 /etc/resolv.conf
done
} > /etc/resolv.conf
echo "/etc/resolv.conf 文件内容"
cat /etc/resolv.conf
