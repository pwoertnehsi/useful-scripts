$serverAlias = Read-Host -Prompt "Server name"
$serverIP = Read-Host -Prompt "IP"
$username = Read-Host -Prompt "Username"
$port = Read-Host -Prompt "Port (Default: 22)"
$generateKey = Read-Host -Prompt "Generate a keypair for the new host? Y/N"

if ($port -eq "") {
	$port = 22
}

@"
Host "$serverAlias"
	HostName $serverIP
	User $username
	Port $port	
"@ | Add-Content -Path $HOME\.ssh\config

if (($generateKey -eq "Y") -or ($generateKey -eq "y")) {

if (-not (Test-Path -Path $HOME\.ssh\keys)) {

	Write-Host "Creating a folder to store keys in (~/.ssh/keys)..."
	New-Item -Path $HOME\.ssh\keys -ItemType Directory
	ssh-keygen -t ed25519 -f $HOME\.ssh\keys\id_ed25519_$serverAlias

@"
	IdentityFile ~/.ssh/keys/id_ed25519_$serverAlias
	IdentitiesOnly yes
"@ | Add-Content -Path $HOME\.ssh\config

	type $HOME\.ssh\keys\id_ed25519_$serverAlias.pub | ssh $username@$serverIP -p $port "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys"
}

else {

	ssh-keygen -t ed25519 -f $HOME\.ssh\keys\id_ed25519_$serverAlias
@"
	IdentityFile ~/.ssh/keys/id_ed25519_$serverAlias
	IdentitiesOnly yes
"@ | Add-Content -Path $HOME\.ssh\config

	type $HOME\.ssh\keys\id_ed25519_$serverAlias.pub | ssh $username@$serverIP -p $port "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys"

}

}

Write-Host "Done! Type 'ssh $serverAlias' to connect to the host."
