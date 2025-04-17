$all_creds = cmdkey /list

# $pattern = "Microsoft" (zb für MS Einträge)

foreach ($cred in $all_creds) {
    if ($cred -match "target=(.+)") {
        $cred_name = $matches[1] # reg match auf alles nach target=
        # optional: if ($cred_name -like "*$pattern*") { aktion zum löschen }
        cmdkey /delete:$cred_name
        Write-Output $cred_name
    }
}