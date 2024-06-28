#Examle log line: 1225411107 Test Dude | YOURCOMPANY 29-12-2022 08:25:50 29-12-2022 08:28:54 adadmin RemoteControl {7a821bfd-c610-4c8d-8abb-c82fe4d83bc2}
#Delimited by Tabs
$lastconnectionsstr = @()
$connections = @()
foreach($line in Get-Content "C:\Program Files (x86)\TeamViewer\Connections_incoming.txt" -ErrorAction SilentlyContinue) {
   $fields = $line.Split("`t")
   
   if ($fields.count -eq 8) {
        $peer_id = $fields[0]
        $peer_name =$fields[1]
        $time_started = [Datetime]::ParseExact($fields[2], 'dd-MM-yyyy HH:mm:ss', $null)
        $time_ended = [Datetime]::ParseExact($fields[3], 'dd-MM-yyyy HH:mm:ss', $null)
        $time_total = New-TimeSpan –Start $time_started –End $time_ended
        $time_ago = New-TimeSpan –Start $time_ended –End $(Get-Date)
        $windows_session = $fields[4]
        
        $connection_details = [PSCustomObject]@{
          peer_id = $peer_id
          peer_name = $peer_name
          time_started = $time_started
          time_ended = $time_ended
          time_total = $time_total
          time_ago = $time_ago
          windows_session = $windows_session
        }
        $connections += $connection_details
   }
}

#Write last 5 foreign connections to field
$last_5_foreign_connections = $connections | Where-Object -FilterScript {$_.peer_name -notlike "*YOURCOMPANY*"} | Select-Object -last 5
foreach($connection in $last_5_foreign_connections) {
  $last_5_foreign_connections_str += "$($connection.time_started): $($connection.peer_name) ($($connection.peer_id)) was connected for $($connection.time_total.minutes) minutes $([Environment]::NewLine)"
}
Ninja-Property-Set Last6ForeignTvConnections $last_5_foreign_connections_str


$foreign_connections = $last_5_foreign_connections | Where-Object -FilterScript {$_.time_ago.totalhours -lt 6}
if ($foreign_connections.count -gt 1) {
  return "connections_found $([Environment]::NewLine) $last_5_foreign_connections_str"
}
return "no_connections_found"