#!/bash/bin

## Need to create Varaible conf file for below varaibles to be used in script:
#user=ec2-user
#huser=ec2-user
#key=key.pem
#zeppelin=10.0.248.17
#tempdir=`pwd`/temp/

source ./variable.conf

[ -e MasterIp.list ] && rm MasterIp.list
[ -e SlaveIp.list  ] && rm SlaveIp.list
[ -e MainFile.list  ] && rm MainFile.list
[ -d "$tempdir" ] && rm -r $tempdir; mkdir $tempdir || mkdir $tempdir

`aws autoscaling describe-auto-scaling-groups | jq '.AutoScalingGroups[].Tags[] | select(.Key=="c-jiraid") | .Value' | sed 's/"//g'  | sort | uniq > ${tempdir}ticket.no`
ttickets=$(wc -l ${tempdir}ticket.no)

echo "Total no of ASG's are: $ttickets"
echo -e "\n"
for tno in `cat ${tempdir}ticket.no`


        do
	echo "#################"
	echo "Checking for $tno"
	echo "################"

	echo -e "\n"
            `aws autoscaling describe-auto-scaling-groups | jq ".AutoScalingGroups[].Tags[] | select(.Value==\"$tno\") | .ResourceId" | grep -i "presto" | sed 's/"//g' > ${tempdir}${tno}_file`
echo "ASG's for $tno are:"
cat ${tempdir}${tno}_file
echo -e "\nChecking if this is a Presto Cluster for $tno"

if [ -s "${tempdir}${tno}_file" ]

	then
	echo "This is a Presto Cluster because asg name contains \"Presto\":  $tno"

for asg in `cat ${tempdir}${tno}_file`

	do
		
		count=`aws autoscaling describe-auto-scaling-groups --auto-scaling-group-name "$asg" | jq '.AutoScalingGroups[].Instances[].InstanceId' | sed 's/"//g' | wc -l`
echo -e "\nASG: $asg has $count instances"
if [ $count -eq 1 ]
	then
		echo "Checking if this is the Master node"
		echo -e "\n"

	instance=`aws autoscaling describe-auto-scaling-groups --auto-scaling-group-name "$asg" | jq '.AutoScalingGroups[].Instances[].InstanceId' | sed 's/"//g'`
		ip=`aws ec2 describe-instances --instance-id $instance | jq '.Reservations[].Instances[].PrivateIpAddress' | sed 's/"//g'`
		ssh -o "StrictHostKeyChecking no" $user@$ip -i $key [[ -d .prestoadmin  ]] && Available=0 || Available=1
		if [ $Available == 0 ];
			then
				echo "This one is Master node for $tno with name $asg and IP:$ip"
				echo "[${asg}_Master]" > ${tempdir}MasterIp.list
				echo "since .prestoadmin directory only exist on master node"
				echo "$ip" >> ${tempdir}MasterIp.list ##Just to filter the master node
			else
				echo -e "\nThis is Slave since with uniq catch i.e. it has one node ASG: $asg with IP: $ip"
				echo "$ip" >> ${tempdir}SlaveIp.list ## Slave ip for single node catch
			fi
			
	else
		echo -e "\nSlave/Worker ASG:$asg"		
		i_r=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-name "$asg" | jq '.AutoScalingGroups[].Instances[].InstanceId' | sed 's/"//g' | tee ${tempdir}instance.list)
		
		for asg_i in `cat ${tempdir}instance.list`
			
			do
				ip=`aws ec2 describe-instances --instance-id $asg_i | jq '.Reservations[].Instances[].PrivateIpAddress' | sed 's/"//g'`
				echo "$ip " >> ${tempdir}SlaveIp.list
			done
	fi



done

cat ${tempdir}MasterIp.list >> MainFile.list

echo " " >> MainFile.list

sed -i "1s/^/[${asg}_Slave]\n/" ${tempdir}SlaveIp.list

cat ${tempdir}SlaveIp.list >> MainFile.list

echo " " >> MainFile.list
echo " " > ${tempdir}MasterIp.list
echo " " > ${tempdir}SlaveIp.list

sleep 2

else
	`aws autoscaling describe-auto-scaling-groups | jq ".AutoScalingGroups[].Tags[] | select(.Value==\"$tno\") | .ResourceId"  | sed 's/"//g' > ${tempdir}${tno}_file`
	noPresto=$(cat ${tempdir}${tno}_file | sed 's/^/\t\t/g')
	echo -e "\t\t\t##################################################################"
	echo -e "\t\tThis Ticket no : $tno is not for Presto Cluster, below are the ASG's"
	echo -e "$noPresto"
	echo -e "\t\tChecking next one"
	echo -e "\t\t\t##################################################################"

fi

done

echo "Host File is created with name: `pwd`/MainFile.list"
cp MainFile.list hosts
echo "Taking backup of existing file on Zeppelin"
ssh -o StrictHostKeyChecking=no -i $key $huser@$zeppelin "cd /etc/ansible; cp hosts hosts_$(date +"%Y%m%d%H%M%S")" && echo "Backup completed" || echo "Backup got some errors" 
echo "scp hadoop@Zeppelin file: MainFile.list ..."
scp -o  StrictHostKeyChecking=no -i $key MainFile.list hosts $huser@$zeppelin:/etc/ansible && echo "File placed at /etc/ansible" || echo "Error while scp check the key/host/vpn"