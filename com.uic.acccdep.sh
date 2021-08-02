#!/bin/bash
#
#
#Created by William Mehilos, University of Illinois (wmehilos@uic.edu)
#with heavy inspiration drawn from similar work done by John Mahlman (jmahlman@uarts.edu)
#
#Purpose: Install and run DEPNotify at enrollment time and display policy progress to end user.
#This script gets installed with DEPNotify, the LaunchDaemon plist that will launch it, and any
#supporting files. 
#
#05/18/2019
#
#
#Variable Definitions
JAMFBIN=/usr/local/bin/jamf
#Get OS version numbers into their respective variables
OLDIFS = $IFS
IFS='.' read OS_MAJ OS_MIN OS_PAT <<< "$(/usr/bin/sw_vers -productVersion)"
IFS=$OLDIFS
OS_BLD=$(sw_vers -buildVersion)
PROC="$(/usr/sbin/sysctl -n machdep.cpu.brand_string | awk '{print $1}')"
# Moved Apple Silicon/Rosetta checks to preinstall on ACCC DEPNotify-1.1.pkg
setupDone="/Library/Application Support/JAMF/Receipts/.depCompleted"
DNLOG=/var/tmp/depnotify.log
CURRENTUSER=$(/usr/bin/python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");')

#If for some reason DEP setup has already been successfully completed, remove script and LD
if [[ -f "${setupDone}" ]]; then
	#Remove LD
	/bin/rm -Rf /Library/LaunchDaemons/com.uic.acccdep.launch.plist
	#Remove Self
	/bin/rm -Rf "$0"
	exit 0
fi

#Hold...hold..., wait until a user is logged in completely before doing anything.
if pgrep -x "Finder" \
&& pgrep -x "Dock" \
&& [[ "$CURRENTUSER" != "_mbsetupuser" ]] \
&& [[ ! -f "${setupDone}" ]]; then	
	
	#Grab some coffee
	/usr/bin/caffeinate -d -i -m -u -s &
	caffeinatepid=$!
	
	#Preempt any other installers
	killall Installer
	#Then rest to contemplate what you've done
	sleep 5
	
	#Configure DEPNotify starting window
	echo "Command: MainTitle: Welcome to Your New Mac!" >> $DNLOG
	echo "Command: Image: /var/tmp/ts.png" >> $DNLOG
	echo "Command: WindowStyle: NotMoveable" >> $DNLOG
	echo "Command: Determinate: 8" >> $DNLOG
	echo "Command: MainText: This Mac is installing all necessary software and running some configuration tasks. \
	Please do not interrupt this process or close the lid. This will take about a half hour to complete unless there are large OS updates to install from Apple. Your Mac will restart when it is complete. \
	Additonal software like alternative browsers, Adobe CC products, and plugins can be found in Software Center.app found in the Applications folder or Launchpad. \" >> $DNLOG
	
	#Invoke DEPNotify app binary
	sudo -u "$CURRENTUSER" /var/tmp/DEPNotify.app/Contents/MacOS/DEPNotify -fullScreen &
	echo "Status: Setting FileVault 2 to Enable" >> $DNLOG
	"$JAMFBIN" policy -event depNotifyFV
	echo "Status: Downloading Microsoft Office 2019" >> $DNLOG
	"$JAMFBIN" policy -event depNotifyDLO365
	echo "Status: Installing Microsoft Office 2019" >> $DNLOG
	"$JAMFBIN" policy -event depNotifyInstO365
	echo "Status: Downloading Microsoft Defender for Endpoint" >> $DNLOG
	"$JAMFBIN" policy -event depNotifyWDAVDL
	echo "Status: Installing Microsoft Defender for Endpoint" >> $DNLOG
	"$JAMFBIN" policy -event depNotifyWDAVIN
	#Changed this from a simple pgrep Microsoft to the actual process names to not interfere with Defender
	#We have to kill MAU here to ensure a successful reboot at the end
	kill $(pgrep Microsoft\ AutoUpdate)
	#Run it again to shut up Error Reporting 
	kill $(pgrep Microsoft\ Error\ Reporting)
	#Unload MAU LaunchDaemon
	launchctl unload /Library/LaunchDaemons/com.microsoft.autoupdate.helper.plist
	#NoMAD not getting installed anymore
	#if [ $OS_MIN <= 14 ] && [ $OS_MIN != 0 ]; then
		#echo "Status: Downloading and installing NoMAD Authentication" >> $DNLOG
		#"$JAMFBIN" policy -event depNotifyNoMAD
		##Unload NoMAD LaunchAgent, to shut it up, then shut it down
		#/bin/launchctl unload /Library/LaunchAgents/com.trusourcelabs.NoMAD.plist
		#kill $(pgrep NoMAD)
	#fi
	#echo "Status: Downloading and installing Adium XMPP Client (Trillian available in Software Center)" >> $DNLOG
	#"$JAMFBIN" policy -event depNotifyAdium
	echo "Status: Downloading and installing Zoom" >> $DNLOG
	"$JAMFBIN" policy -event depNotifyWebex
	#Quit Webex
	sleep 10
	kill $(pgrep Zoom)
	kill $(pgrep Webex)
	#Removing on-prem printers, since most of us aren't on-prem
	#echo "Status: Downloading and installing ACCC Printer Configurations" >> $DNLOG
	#"$JAMFBIN" policy -event depNotifyACCCPrint
	echo "Status: Downloading and Installing Cisco AnyConnect VPN" >> $DNLOG
	"$JAMFBIN" policy -event depNotifyVPN
	echo "Status: Finalizing and cleaning up." >> $DNLOG
	"$JAMFBIN" policy -event depNotifyFinalize
	#Moving SUS here, since sometimes it can cause unscheduled reboots to complete OS updates
	echo "Status: Checking with Apple for Software Updates. Your Mac will reboot soon." >> $DNLOG
	"$JAMFBIN" policy -event depNotifyAppleSUS
	echo "Command: Alert: We're all done here. Your Mac will reboot automatically. When logging in, you will be prompted to enable FileVault. Please do so. Crashplan will launch soon after that first login. This application keeps your home directory backed up, but it might take some time to connect to its backup engine. " >> $DNLOG
	sleep 60

	#call system reboot
	shutdown -r now 
	#Quickly try to kill off LD and script
	#Unload LD	
	/bin/launchctl unload /Library/LaunchDaemons/com.uic.acccdep.launch.plist
	#Kill self
	/bin/rm -Rf "$0"
	
	
	#Uncomment these lines if you need DEPNotify to do something after the last enrollment policy finishes
# 	#Pop an Ambien to counter act that coffee
# 	#kill $caffeinatepid	
# 	
# 	#Show user a restart button and message
# 	#echo "Command: Alert: Your Mac has completed it's initial setup. It will reboot automatically in 1 minute, or you can manually reboot after dismissing this message. As your Mac reboots, you will be asked to enable FileVault.\
# 	#After the reboot is complete, and after you log in, you will be prompted to sign into two pieces of software, Code 42 Crashplan, which will backup your home directory automatically, and NoMAD, which will keep your Mac's password in sync with your UIC common password." >> $DNLOG
# 	#echo "Command: MainText: We\'re all done here! Please reboot to complete setup." >> $DNLOG
# 	#echo "Command: ContinueButtonRestart: Restart" >> $DNLOG



fi
exit 0	
	
