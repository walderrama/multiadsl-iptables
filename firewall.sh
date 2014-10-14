#!/bin/bash
############ CONF GRAL ############

adsl_ifaces=(eth2     eth3          ...     eth0.14)
adsl_ips=(10.0.2.2      10.0.3.2        ...     10.0.14.2)
adsl_gws=(10.0.2.1      10.0.3.1        ...     10.0.14.1)
adsl_weight=(1          1               ...     1)
adsl_upload=(256        256             ...     256)

############ THE SCRIPT ############
#PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
test "$1" == "debug" && set -x
test "$1" == "show"  && iptables() { echo iptables "$@"; } && ip() { echo ip "$@"; } && tc() { echo tc "$@"; } && ifconfig() { echo ifconfig "$@"; }
test "$1" == "loadvars" && return 0


# por cada conexiÃ³n
for ((n=0;n<${#adsl_ifaces[@]};n++)); do
        # doy de alta la interface
        ifconfig ${adsl_ifaces[n]} ${adsl_ips[n]} netmask 255.255.255.0 up
        # borro lo viejo
        ip route flush table adsl$((n+1)) 2>/dev/null
        ip rule del from ${adsl_ips[n]} table adsl$((n+1)) 2>/dev/null
        tc qdisc del dev ${adsl_ifaces[n]} root 2>/dev/null
        # baja latencia y queue en los adsl , usamos tbf que rulea para esto
        tc qdisc add dev ${adsl_ifaces[n]} root tbf rate ${adsl_upload[n]}kbit latency 50ms burst 1540
        # armo la tabla de routeo â€œadsl$nâ€ copiando la tabla main y cambiando el default gateway
        while read line ;do
                test -z "${line##default*}" && continue
                test -z "${line##nexthop*}" && continue
                ip route add $line table adsl$((n+1))
        done < \
        <(/sbin/ip route ls table main)
        ip route add default table adsl$((n+1)) proto static via ${adsl_gws[n]} dev ${adsl_ifaces[n]}
        # creo la regla de routeo para salir por esta talba si tenga esta source address
        ip rule add from ${adsl_ips[n]} table adsl$((n+1))
        # guardo para crear el balanceo
        multipath="$multipath nexthop via ${adsl_gws[n]} dev ${adsl_ifaces[n]} weight ${adsl_weight[n]}"
done
# ahora creo el default gw con multipath en la tabla main
ip route del default 2>/dev/null
ip route add default proto static $multipath
# flush de cache de ruteo
ip route flush cache


############ IPTABLES ############
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X

############ NAT ############
# - hago masquerade por cada interface/conexiÃ³n
#for ((n=0;n<${#adsl_ifaces[@]};n++)); do
#        iptables -t nat -A POSTROUTING -o ${adsl_ifaces[n]} -j MASQUERADE
#done

############ CONNTRACK ############
# restauro la marka en PREROUTING antes de la desiciÃ³n de ruteo.
iptables -t mangle -A PREROUTING -j CONNMARK --restore-mark

# CONNTRACK para elmultipath
# creo una tabla aparte
iptables -t mangle -N my_connmark
# y hago pasar los packetes que aÃºn nunca fueron markados
# (siempre serÃ¡n paquetes que inician una conexiÃ³n)
iptables -t mangle -A FORWARD -m mark --mark 0 -j my_connmark
# una vez procesado, borro la marka por si quiero usar las markas para otras cosas
# como x ej QoS y control ancho de banda
iptables -t mangle -A FORWARD -j MARK --set-mark 0x0

# y ahora el contenido de la tabla aparte: my_conntrack
# para la LAN no me hace falta conntrack ya que tengo una sola interface
iptables -t mangle -A my_connmark -o eth1 -j RETURN
# por cada conexiÃ³n
for((n=0;n<${#adsl_ifaces[@]};n++)); do
        #asocio una marka a cada interfaz
        iptables -t mangle -A my_connmark -o ${adsl_ifaces[n]} -j MARK --set-mark 0x$((n+1))
        iptables -t mangle -A my_connmark -i ${adsl_ifaces[n]} -j MARK --set-mark 0x$((n+1))
done
# la guardo para despues poder hacer el â€“restore-mark en PREROUTING
iptables -t mangle -A my_connmark -j CONNMARK --save-mark

# por ultimo uso ip ru para hacer que el packete use la tabla de ruteo que le corresponde
for ((n=0;n<${#adsl_ifaces[@]};n++)); do
        ip ru del fwmark 0x$((n+1)) table adsl$((n+1)) 2>/dev/null
        ip ru add fwmark 0x$((n+1)) table adsl$((n+1))
done




