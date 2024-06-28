# This script uses the TeamViewer15_Logfile.log file, which is updated in real-time.
# It detects sessions that are currently in progress and connections that have already ended.
# Examples
# 2024/06/28 20:23:37.280  3160  3604 S0   CPersistentParticipantManager::AddParticipant: [1651063400,876631011] type=6 name=Joe Doe | Pro IT Services
# 2024/06/28 22:49:14.140  3160  3608 S0   CPersistentParticipantManager::RemoveParticipant: [1651063400,2002352381]
# Delimited by one or more spaces
# Timestamps are local imezone

# If the following text is found in the peer name, the connection will be considered friendly
$friendly_identifier = "TORUTEC GmbH"
$connections = @()
foreach($line in Get-Content "C:\Program Files (x86)\TeamViewer\TeamViewer15_Logfile.log" -Encoding UTF8 -ErrorAction SilentlyContinue) {
    # Check if the log line contains information on a new participant
    if ($line -match "CPersistentParticipantManager::AddParticipant:") {
        # A new participant joined

        # Split the log line into parts based on the first occurrence of "CPersistentParticipantManager::AddParticipant:"
        $main_parts = $line -split "CPersistentParticipantManager::AddParticipant:", 2
        
        # Extract the initial parts of the log line (timestamp, process id, etc.)
        $initial_parts = $main_parts[0] -split "\s+", 6
        
        # Extract variables from the initial parts
        $timestamp = $initial_parts[0] + " " + $initial_parts[1]
        $time_started = [Datetime]::ParseExact($timestamp, 'yyyy/MM/dd HH:mm:ss.fff', $null)
        $time_ago =  New-TimeSpan –Start $time_started –End $(Get-Date)
        # Extract the participant info
        $participant_info = $main_parts[1].Trim()
        
        # Use regex to extract participant IDs, type, and name
        $participant_ids_match = [regex]::Match($participant_info, "\[(.+?)\]")
        $type_match = [regex]::Match($participant_info, "type=(\d+)")
        $name_match = [regex]::Match($participant_info, "name=(.+)")
        
        if ($participant_ids_match.Success -and $type_match.Success -and $name_match.Success) {
            $participant_ids = $participant_ids_match.Groups[1].Value.Split(',')
            $participant_id_1 = $participant_ids[0] # That is the connecting TeamViewer ID
            $participant_id_2 = $participant_ids[1] # It's unknown what this ID is
            $type = $type_match.Groups[1].Value
            $name = $name_match.Groups[1].Value
            
            if ($type -ne 3) {
                # type=3 is the local device (the host) joining the session. We only care for remote parties joining the session which is usually type=6
                $connection = [PSCustomObject]@{
                    time_started     = $time_started
                    time_ago = $time_ago
                    peer_id  = $participant_id_1
                    peer_name            = $name
                }
                $connections += $connection
            }

        } 
    }
}

# Filter out friendly connections
$foreign_connections = $connections | Where-Object -FilterScript {$_.peer_name -notlike "*$friendly_identifier*"}
# Filter out old connections
$foreign_connections = $foreign_connections | Where-Object -FilterScript {$_.time_ago.totalhours -lt 24}

if ($foreign_connections.count -gt 0) {
    Write-Host "foreign_connections_found"
    foreach ($foreign_connection in $foreign_connections) {
        Write-Host "$($foreign_connection.peer_name) ($($foreign_connection.peer_id)) started a connection on $($foreign_connection.time_started.ToString("dd.MM.yyyy HH:mm:ss"))"
    }
} else {
    Write-Host "no_foreign_connections_found"
}