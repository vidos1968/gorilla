# cli.tcl
#
# Command-line module for Password Gorilla
#
# Usage: gorilla ?options|database?
#
# gorilla testdb.psafe3				-> opens an existing db (GUI mode)
# gorilla -cli|--comand-line	-> enters the parsing loop and waits for commands
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation; either version 2 of the License, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
# for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 675 Mass Ave, Cambridge, MA 02139, USA.

# A copy of the GNU GPL may be found in the LICENCE.txt file in the main
# gorilla/sources directory.
				
namespace eval ::cli {
	# FIXME: Option -h causes error "Tk not found"
	# Error can be fixed if argv is cleaned at the very beginning before
	# requiring package Tk.
	# set ::gorilla::argv $argv
	# set argv ""
	#

	array set Commands {
		open					cli::Open
		quit					cli::Quit
		list					cli::List
		edit					cli::Edit
		save					cli::Save
		find					::cli::Find
		help					::cli::Help
	}

	set FieldList [list uuid group title user notes password url \
		create-time last-pass-change last-access lifetime last-modified]
		
} ;# end eval cli

proc ::cli::Help { args } {
	set output ""
	switch [lindex $args 0] {
		commands { return [list OK [array names ::cli::Commands] ] }
		list { set output "list -field fieldname rn   -> list single record rn
list -field fieldname      -> lists all records for fieldname
list -field                -> lists all fieldnames
list rn                   -> list single record
list -group groupname      -> lists all records in a group
list -group                -> lists all groupnames with valid entries"
		}
		open { set output "open database ?password?" }
		save { set output "save    -> saves the current database" }
		edit { set output "edit fieldname recordnumber" }
		find { set output "find text                    find text in all records and fields
find -field fieldname text    find text in fieldname of all records"
		}
		help { set output "\"help commands\" shows possible commands
\"help <command-name>\" shows help for a single command" }
		quit { set output "quits Passwort Gorilla" }
		default { return [list ERROR "Command unknown"] }
	} ;# end switch
	return [list OK $output]
} ;# end of proc ::cli::Help

proc ::cli::Save { } {
	set nativeName [file nativename $::gorilla::fileName] 
	if { ! [ file writable $nativeName ]	} {
		return [list ERROR "$::gorilla::fileName is write-protected."]
	}
	
	set majorVersion 2
	
	if {[$::gorilla::db hasHeaderField 0]} {
		set version [$::gorilla::db getHeaderField 0]
		if {[lindex $version 0] == 3} {
			set majorVersion 3
		}
	}
	
	if { [catch {pwsafe::writeToFile $::gorilla::db $nativeName $majorVersion } oops] } {
		return [list ERROR "$oops"]
	}
	
	# backup?
	return [list OK "Saved database [ file tail $::gorilla::fileName ]"]

	# Todo: unset stuff
	
} ;# end of proc Save

proc ::cli::Edit { args } {
	# edit field rn

	if { ! [info exists ::gorilla::db] } {
		return [list ERROR "No database available. Please type: \"open <database>\"."]
	}
	# check options
	if { [llength $args] < 2 } {
		return [list ERROR "Argument missing. Should be \"Edit field rn\"."]
	 }
	set field [lindex $args 0]
	if { [lsearch $::cli::FieldList $field] < 0 } {
		return [list ERROR "Invalid field. Must be: $::cli::FieldList"]
	}
	set rn [lindex $args 1]
	if { [lsearch [$::gorilla::db getAllRecordNumbers] $rn] < 0} {
		return [list ERROR "Invalid record-number. Possible values: 1-[lindex [$::gorilla::db getAllRecordNumbers] end]"]
	}
	
	# edit string with line-at-a-time mode
	# c.f http://wiki.tcl.tk/16139: tcl-readline
	puts "Old string $field #$rn: [ ::gorilla::dbget $field $rn ]"
	puts -nonewline "New string $field #$rn: "
	flush stdout
	gets stdin newString
	gorilla::dbset $field $rn $newString
	set ::gorilla::dirty 1
	return [list OK "$field #$rn: [ ::gorilla::dbget $field $rn ]"]
} ;# end of proc ::cli::Edit

proc ::cli::Norc {} {
	# This option is useful only for Windows users who want to use the registry
	set ::gorilla::preference(norc) 1
}

proc ::cli::Quit {} {
	if { $::gorilla::dirty } {
		puts -nonewline "Database has changed. Save it? ([mc yes]|[mc no]) :"
		flush stdout
		set choice [read stdin 1]
		if { $choice eq [string index [mc yes] 0] } {
			::cli::Save
			puts "Database saved"
		}
	}
	exit
} ;# end of proc ::cli::Quit

proc ::cli::GetGroupNames {} {
	# Todo: init variable ::cli::AllRecordNumbers
	set output [list ]
	foreach number [$::gorilla::db getAllRecordNumbers] {
		lappend output [ ::gorilla::dbget group $number ]
	}
	return [lsort -unique $output]
} ;# end of proc cli::GetGroupNames

# http://wiki.tcl.tk/14693
proc ::cli::enableRaw {{channel stdin}} {
     exec /bin/stty raw -echo <@$channel
}

proc ::cli::disableRaw {{channel stdin}} {
	 exec /bin/stty -raw echo <@$channel
}

proc ::cli::Open { fileName {password ""} } {
	# Note: for test purposes the filename is preset!
	# set fileName [file join $::gorillaDir ../unit-tests testdb.psafe3]
	# set password test
	
	if { ![file exists $fileName] } {
		return [ list ERROR [mc "Could not find $fileName."] ]
		# mc ERROR-OpenError-nofile
	} ;# end if

	if {$::gorilla::dirty} {
		puts "should we save the db?"
	}

	if { $password eq "" } {

		puts -nonewline "Please enter password:"
		flush stdout

		if {$::tcl_platform(platform)!="unix"} {
      # FIXME:  This routine only works on unix.  On other platforms, the
      # password is still echoed to the screen as it is typed.
      gets stdin password
    } else {
			::cli::enableRaw
			gets stdin password
			::cli::disableRaw
		}
	}
	
	set ::gorilla::collectedTicks [list [clock clicks]]
	gorilla::InitPRNG [join $::gorilla::collectedTicks -] ;# not a very good seed yet

	if { [catch {
					set newdb [pwsafe::createFromFile $fileName $password ::gorilla::openPercent]
				} oops ] } {
		return [list ERROR $oops]
	}
	
	# if newdb eq "" then return [list ERROR [mc "Could not open $filename"]]

	if {[info exists ::gorilla::db]} {
		itcl::delete object $::gorilla::db
	}

	# initialization of database variables
	set nativeName [file nativename $fileName]
	set ::gorilla::fileName $fileName
	set ::gorilla::db $newdb
	set ::gorilla::dirty 0
	set ::cli::GroupNames [cli::GetGroupNames]
	
# puts "Debug fileName: $fileName newdb: $newdb"
	
	return [ list OK [mc "Ok. Actual database is %s." $fileName] ]
	# mc STATUS-Open-ok
} ;# end of proc ::cli::Open

proc ::cli::CheckRecordNr { rn } {
	# range
	if { $rn ni [$::gorilla::db getAllRecordNumbers] } {
		return [list ERROR  "Invalid record-number. Possible values: 1-[lindex [$::gorilla::db getAllRecordNumbers] end]"]
	}
	return [list OK $rn]
} ;# end of proc

proc ::cli::List { args } {
	# list -field fieldname rn   -> list single record rn
	# list -field fieldname      -> lists all records for fieldname
	# list -field                -> lists all fieldnames
	# list rn                   -> list single record
	# list group groupname      -> lists all records in a group
	# list group                -> lists all groupnames with valid entries

	if { ! [info exists ::gorilla::db] } {
		return [list ERROR "No database available. Please type: \"open <database>\"."]
	} ;# end if

	# check list options

	if { $args eq "" } {
		# list all records per title? Not helpful with a large db.
		return [list ERROR "Missing option. Should be: group, field or ."]
	} ;# end if
	
	if { [string is integer [lindex $args 0]] } {
		set result [ ::cli::CheckRecordNr [lindex $args 0] ]
		if { [lindex $result 0] eq "ERROR" } {
			return $result
		} else {
			set rn [lindex $result 1]
			set output "Contents of record $rn:\n--------------------"
			foreach item $::cli::FieldList {
				append output "[format "%-*s" 18 \n$item]:[ ::gorilla::dbget $item $rn ]"
			}
			return [list OK $output] 
		}
	} ;# end if

	set option [lindex $args 0]

	# array set cli::ListOptionsExecute { option execute }
	# eval cli::OptionsExecute($option) $args
	
	switch $option {
		-field {
			set fieldname [lindex $args 1]
			if { $fieldname ne ""} {
				if { $fieldname ni $::cli::FieldList } {
					return [list ERROR "Invalid field. Must be: $::cli::FieldList"]
				}
				set rn [lindex $args 2]
				if { $rn ne ""} {
					set result [ ::cli::CheckRecordNr $rn ]
					if { [lindex $result 0] eq "ERROR" } {
						return $result
					}
					# list -field fieldname rn
					return [list OK "$fieldname #$rn: [ ::gorilla::dbget $fieldname $rn ]"]
				} else {
					# list -field fieldname
					set output ""
					foreach number [$::gorilla::db getAllRecordNumbers] {
						append output "$fieldname #$number: [ ::gorilla::dbget $fieldname $number ]\n"
					}
					# return [list OK $output]
				}
			} else {
				# list -field
				return [list OK $::cli::FieldList]
			}
		}
		-group {
			set groupname [lindex $args 1]
			if { $groupname ne ""} {
				if { $groupname ni [::cli::GetGroupNames] } {
					# Todo: {} eq root
					return [list ERROR "Unknown group. Should be: [join [::cli::GetGroupNames] ", "]" ]
				} ;# end if
				# list group groupname
				set output "+++ Found:"
				foreach number [$::gorilla::db getAllRecordNumbers] {
					if { [::gorilla::dbget group $number] eq $groupname } {
						append output "\nTitle #$number: [::gorilla::dbget title $number]"
					} ;# end if
				}
				# return [list OK $output]
			} else {
				# list group
				return [ list OK "+++ Groups with valid entries are:\n[::cli::GetGroupNames]" ]
			}
		}
		default {
			return [list ERROR  "Invalid option. Must be: field, group"]
		}
	} ;# end switch
	
	return [list OK $output]

} ;# end of proc ::cli::List

proc ::cli::Find { args } {
	# find the passed text in the records
	# Usage:
	# find text                    find text in all records and fields
	# find -field fieldname text    find text in fieldname of all records
	# 
	# args - text to search
	#
	# make an AND search if text has multiple words?

	if { ! [info exists ::gorilla::db] } {
		return [list ERROR "No database available. Please type: \"open <database>\"."]
	}

	set text [lindex $args 0]
	if { $text eq "" } { return [list ERROR "Usage: find ?options? text"] }
	
	set found [list ]
	set totalRecords [llength [$::gorilla::db getAllRecordNumbers]]

	if { $text eq "-field" } {
		set fieldname [lindex $args 1]
		if { $fieldname eq ""} { return [list ERROR "Missing fieldname."]	}
		if { $fieldname ni $::cli::FieldList } {
			return [list ERROR "Invalid field. Must be: $::cli::FieldList"]
		}
		set text [lindex $args 2]
		if { $text eq "" } { return [list ERROR "Missing search text."]	}
		
		# find field fieldname
		foreach rn [$::gorilla::db getAllRecordNumbers] {
			if { [string match *$text* [::gorilla::dbget $fieldname $rn] ] } {
				lappend found [list $fieldname "#$rn"]
			}
		}
	} else {
		# find text
		foreach field $::cli::FieldList {
			foreach rn [$::gorilla::db getAllRecordNumbers] {
				if { [string match *$text* [::gorilla::dbget $field $rn] ] } {
					lappend found [list $field "#$rn"]
				}
			} ;# end foreach rn
		} ;# end foreach field
	} ;# end if { $text eq "field" }

		# set percent [expr {int(100.*$recordsSearched/$totalRecords)}]
		# set ::gorilla::status "Searching ... ${percent}%"
		# set cs $::gorilla::preference(caseSensitiveFind)

	if { [llength $found] == 0 } {
		return [list ERROR  [mc "Did not find \"%s\"." $text]]
	}

	return [ list OK [mc "found \"%s\" in: %s" $text [join $found ", "] ] ]

} ;# end of proc find

proc ::cli::ParseCommand { line } {
	# check if the passed command is valid. Return the line without
	# command name
	#
	# line - The line entered by the user on the console
	#

	# get a proper list without unnecessary white spaces
	set line [ regexp -all -inline {\S+} $line ]
	set command [lindex $line 0]

	if { ! [info exists ::cli::Commands($command)] } {
		return [list ERROR "Unknown command: \"$command\". - Possible commands:\
			[join [array names ::cli::Commands] ", "]"] 
	}
	return [list OK "$::cli::Commands($command) [lrange $line 1 end]"]
}

proc ::cli::MainLoop { } {
	# enters the main loop for the command-line module
	#
	# TODO: make use of package vt100 for color, cursor placement ...
	# replace gets by a editable input routine like Tcl-Readline

	puts "Password Gorilla Command-Line Module ($::gorillaVersion)
Type \"quit\" to exit
\"help commands\" shows possible commands
\"help <command-name>\" shows help for a single command"
	
	gorilla::Init

	set line ""
	while 1 {
		puts -nonewline "> "
		flush stdout
		gets stdin line
		
		set line [ cli::ParseCommand $line ]
		if { [lindex $line 0] eq "ERROR" } {
			puts [lindex $line 1]
		} else {
			set answer [ eval [lindex $line 1] ]
			# [lindex $answer 0] contains OK, ERROR ... perhaps we will need it
			puts [lindex $answer 1]
		}
	} ;# end while
	
	return
}