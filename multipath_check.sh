#!/bin/bash
source /etc/firewall.sh loadvars
#A to M ROOT DNS world servers ip address
#I choose those that seems to accept icmp-echo-requests
root_dnservers="B C D E F I J K L M"
multipath_total=0
for((n=0;n<${#adsl_ifaces[@]};n++)); do
        pong=0
        for letter in $root_dnservers; do
                if(ping -n -c1 -W2 $letter.root-servers.net -I ${adsl_ips[n]} &>/dev/null);then
                        pong=1
                        # el doble espacio antes de dev _does_mather_
                        multipath="$multipath nexthop via ${adsl_gws[n]}  dev ${adsl_ifaces[n]} weight ${adsl_weight[n]}"
                        let multipath_total+=1
                        break
                fi
        done
        #if no one answers
        if [[ $pong == 0 ]];then
                #ejemplo telnet y reset, para un zyxel (opciones 24, 4 y 21)
                # user=user;pass=pass;
                #echo -e "$user\n$pass\n$24\n4\n21\n" | telnet ${adsl_gws[n]} &
                # ejemplo hacer sonar el beep
                #echo -e "\a"
                # ejemplo mail
                # echo â€œip:${adsl_ips[n} iface:${adsl_ifaces[n]}â€ | mail -s â€œse cayo la conexiÃ³n ${adsl_ips[n]}â€ someone@foo.bar
                # logueo para futuro anÃ¡lisis
                echo `date`" la conexion con ${adsl_gws[n]} esta down" >> /var/log/adsl_watchdog.log
    fi
done
#si todos estan caidos dejo todo como estaba
test -z "${multipath}" && exit 1

# cargo en $route el multipath actual
while read line ;do
        test -z "${line##default*}" && begin=1
        test "$begin" == 1 && route="$route ${line}"
done < \
<(/sbin/ip route ls)

# armo el multipath de los que estan up para poder comparar
# tengo que preguntar xq si hay solo un enlace up, la sintaxis cambia
if [[ $multipath_total > 1 ]];then
        # el doble espacio antes de proto _does_mather_
        route_multipath=" default  proto static${multipath}"
else
        route_multipath=${multipath#nexthop }
        route_multipath=${route_multipath% weight*}
        route_multipath=" default ${route_multipath/ dev/ dev} proto static"
fi

#printf "%q\n" "${route}"
#printf "%q\n" "${route_multipath}"
# Ya tengo los 2 multipath, ahora puedo comparar
if [[ "$route" != "$route_multipath" ]];then
        # si no son iguales, es hora de cambiar el default gateway
        ip route chg default proto static $multipath
        ip route flush cache
        echo `date`" cambiando default gateway a $multipath" >> /var/log/adsl_watchdog.log
fi
