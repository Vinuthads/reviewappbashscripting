#!/bin/bash

#account with sudo privilage is required
# script to install and run the review app with DB locally on the system
#
#taking the input of the ip address where the db is hosted
echo "==============================================="
echo " invalid input fails the to build the artifact"
echo "==============================================="
read -p " please enter a valid IP or RDS url where the DB is hosted : " ip
echo "==============================================="
#check the packages install


for p in java-21-openjdk maven mariadb-server;do
	echo "checking for the package $p"
	if [[  `sudo yum list installed $p 2> /dev/null` ]];then
		echo " $p is installed"
	else 
		echo "installing package"
		sudo yum install $p -y
	fi
done

#Starting the mariadb service
echo " Verifying the mariadb service"
echo

if [[ `systemctl status mariadb | grep Active | awk '$2 == "active"'` ]];then
	echo "Service is already running"
	systemctl status mariadb | grep Active
else 
	echo " starting the service : mariadb"
	echo "==============================="
	sudo systemctl enable --now mariadb
	echo
	echo "Verifying the service "
	systemctl status mariadb | grep Active
fi

echo "=========================================================================="
echo " All the required package has been installed and services has been started"
echo " Good to go ! "
echo
echo "=========================================================================="

# clone the app file to the directory your running the script

echo " creating the database "
echo "========================================="

#changing to the app directory
cd reviewapp || { echo "reviewapp directory not found"; exit 1; }

#setting up sql

sudo mysql << EOF
DROP DATABASE IF EXISTS reviewapp;
CREATE DATABASE reviewapp;
USE reviewapp;
CREATE USER 'admin'@'%' IDENTIFIED BY 'Password123';
GRANT ALL PRIVILEGES ON reviewapp.* TO 'admin'@'%';
FLUSH PRIVILEGES;
EOF

if [[ $? -eq 1 ]]; then
	echo " database creation failed"
	exit
else
	# verifying the SQL creation
	echo " verifying the creation of database and user "
	echo "============================================"
	echo
	sudo mysql << EOF
	show databases like '%reviewapp%';
	show grants for admin ;
EOF
fi


echo
echo "================================================="

# updating the application.properties file
echo
echo "Updating the propeties file"
echo "================================================="

cat > src/main/resources/application.properties << EOF
spring.application.name=ReviewApp
spring.datasource.url=jdbc:mysql://$ip:3306/reviewapp
spring.datasource.username=admin
spring.datasource.password=Password123

spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.MySQLDialect
spring.jpa.hibernate.ddl-auto=update
EOF

echo
if [[ $? -eq 0 ]] ;then
       	echo "File updated successfully"
else
	echo "file updation failed"
	exit
fi


# Testing and building the artifact
echo 
echo " Testing and building the artifact of the app"
echo "=============================================="
sudo mvn clean package
echo "============================================"
echo " testing finisded , proceeding with building"
echo "============================================"
sudo mvn clean install

if [[ $? -eq 0 ]] ; then
	echo 
	echo " Congrats the app is built successfull, lets run it "
	echo "==================================================="
else
	echo " build failed"
	exit
fi


#creating a system service
echo
echo " Creating a systemd file for the app"

#using tee here becoz using cat with >> , cat runs with sudo but >> runs with the normal user shell privilege which throughs premission delayed error:wq
sudo tee /etc/systemd/system/reviewapp.service << EOF
[Unit]
Description=ReviewApp Spring Boot Application
After=network.target

[Service]
User=root
WorkingDirectory=/opt/reviewapp

ExecStart=/usr/bin/java -jar /opt/reviewapp/reviewapp.jar
SuccessExitStatus=143
TimeoutStopSec=10
Restart=on-failure
RestartSec=5

Environment=SPRING_PROFILES_ACTIVE=prod

[Install]
WantedBy=multi-user.target

EOF

if [[ $? -eq 0 ]];then
       echo " created the file successfully"
else
	echo "reviewapp.service failed to create"
	exit
fi

echo 
echo " =================================================="
echo " moving the jar file to /opt/reviewapp/"
echo

sudo mkdir -p /opt/reviewapp
sudo mv target/ReviewApp-0.0.1-SNAPSHOT.jar /opt/reviewapp/reviewapp.jar

if [[ $? == 0 ]]; then
       echo " moved successfully"
else 
	echo " Unable to move the files"
	exit
fi

echo

# starting the service
echo " starting the review service"
sudo systemctl enable --now reviewapp.service
systemctl status reviewapp.service | grep active

echo "============================================"

#checking the firewall
if [[ `sudo firewall-cmd --state` != 'running' ]] ; then
	echo " Firewall is turned off"
else
	echo " Firewall is turned on , checking for the port"
	echo "=============================================="
	if [[ `sudo firewall-cmd --list-ports| grep -w "8080/tcp"` ]] ;then
		echo " port 8080 is opened "
	else
		sudo firewall-cmd --add-port=8080/tcp --permanent
		sudo firewall-cmd --reload
	fi
fi


echo 
echo "=========================================================="
echo " your app is completely ready you can access it on port 8080"
