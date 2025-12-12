#!/bin/bash

while getopts ":r::a:lh:i::d:" opt; do
	case $opt in
		r) 
			#Restart sequence
			#Checking if the user requested to restart all listed services
			if [ $OPTARG = "all" ]; then
				while IFS= read -r line; do #Reading the services file line by line and restarting them
					systemctl restart $line
					echo "Restarting service $line..."
				done < services
			#Restarting a specific service
			else
				declare -i found=0 #found variable is used to determine if the requested service was found and restarted and the script should exit
				declare -i linenum=0 #linenum variable is used to track current service
				while IFS= read -r line; do #Reading the shortcuts file first because it is optional to have a shortcut for a service
					linenum=linenum+1
					if [ "$line" = "$OPTARG" ]; then #Checking if specified argument is present in shortcuts
						service=$(head -n $linenum services | tail -1) #Getting a systemd service name from 
						systemctl restart $service 
						echo "Restarting $service..."
						found=1 #Declaring that the targeted service is found
					fi
				done < shortcuts
				if [ $found = 1 ]; then #Exiting the script
					exit 1
				else
					while IFS= read -r line; do #Reading the services file if haven't found one matching user input in the shortcuts
						if [ "$line" = "$OPTARG" ]; then
							systemctl restart $line
							echo "Restarting $line..."
							found=1
						fi
					done < services
				fi
				if [ $found = 0 ]; then
					echo "Service not found in the list. Type chup -l to see the list of added services and their respective shorcuts."
				fi
			fi
			;;
		a)
			#Adding new service to the list. systemd service name is provided via argument, then optionally followed by user input shortcut
			echo -n "Shortcut for the service: "
			read shortcut
			if [[ $OPTARG = "all" || $shortcut = "all" ]]; then #Checking if user decided to call their service/shortcut 'all' for some reason
				echo "Service/shortcut for it cannot be named 'all'."
				exit 1
			else
				printf "$OPTARG\n" >> services #Writing new service and it's shortcut to two separate files.
				printf "$shortcut\n" >> shortcuts #Even if the shortcut input is left blank a carriage return is written so that the line number matches between files.  
			fi
			;;
		l)
			#Print all lines from services and shortcuts files
			declare -i linenum=0
			while IFS= read -r line; do
				linenum=linenum+1
				echo "Service #$linenum: $line"
			done < services
			linenum=0
			while IFS= read -r line; do
				linenum=linenum+1
				echo "Shortcut for service #$linenum: $line"
			done < shortcuts
			;;
		h)
			echo "help"
			;;
		i)
			#Get info on added services' statuses
			if [ $OPTARG = "all" ]; then #Pretty much the same concept as in the restart sequence
				while IFS= read -r line; do
					#
					#TODO: make it so that systemd is called only once and it's output is written to a variable
					servicename=$(systemctl status $line | head -1 | tr -d "●" | tr -d "○") #Requesting services' status and leaving only the first line as well as removing the status symbol which gets added later
					status=$(systemctl status $line | head -3 | tail -1) #Leaving only the line which contains status
					if [[ $status == *"Active: active"* ]]; then
						echo -e -n "\e[32m●\e[0m" #Printing the green character for an active service.
						echo "$servicename"
						echo -e "\e[32m$status\e[0m" #Printing the status in green color #TODO: make it so that it is ton fully green but only the 
					elif [[ $status == *"Active: inactive"* ]]; then 
						echo -e -n "\e[91m○\e[0m"
						echo "$servicename"
						echo -e "\e[91m$status\e[0m"
					fi
				done < services
			else
				declare -i found=0
				declare -i linenum=0
				while IFS= read -r line; do
					linenum=linenum+1
					if [ "$line" = "$OPTARG" ]; then
						service=$(head -n $linenum services | tail -1)
						servicename=$(systemctl status $service | head -1| tr -d "●" | tr -d "○")
						status=$(systemctl status $service | head -3 | tail -1)
						if [[ $status == *"Active: active"* ]]; then
							echo -e -n "\e[32m●\e[0m"
							echo "$servicename"
							echo -e "\e[32m$status\e[0m"
						elif [[ $status == *"Active: inactive"* ]]; then
							echo -e -n "\e[91m○\e[0m"
							echo "$servicename"
							echo -e "\e[91m$status\e[0m"
						fi
						found=1
					fi
				done < shortcuts
				if [ $found = 1 ]; then
					break
				else
					while IFS= read -r line; do
						if [ "$line" = "$OPTARG" ]; then
							servicename=$(systemctl status $line | head -1 | tr -d "●" | tr -d "○")
							status=$(systemctl status $line | head -3 | tail -1)
							if [[ $status == *"Active: active"* ]]; then
								echo -e -n "\e[32m●\e[0m"
								echo "$servicename"
								echo -e "\e[32m$status\e[0m"
							elif [[ $status == *"Active: inactive"* ]]; then
								echo -e -n "\e[91m○\e[0m"
								echo "$servicename"
								echo -e "\e[91m$status\e[0m"
							fi
							found=1
						fi
					done < services
				fi
				if [ $found = 0 ]; then
					echo "Service not found in the list. Type chup -l to see the list of added services and their respective shorcuts."
				fi
			fi
			;;
		d)
			echo "delete"
			;;
		\?)
			echo "Invalid option: -$OPTARG" >&2
			exit 1
			;;
		:)
			echo "Option -$OPTARG requires an argument." >&2
			exit 1
			;;
	esac
done


shift $((OPTIND-1))
