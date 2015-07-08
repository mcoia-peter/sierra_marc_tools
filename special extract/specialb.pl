#!/usr/bin/perl
# 
# summon_or_ebsco.pl
#
# Usage:
# ./summon_or_ebsco.pl conf_file.conf [adds / cancels] [ebsco / summon]
#
# Example Configure file:
# 
# logfile = /tmp/log.log
# marcoutdir = /tmp
# z3950server = server.address.org/INNOPAC
# dbhost = 192.168.12.45
# db = postgresDB_Name
# dbuser = dbuser
# dbpass = dbpassword
#
#
# This script requires:
#
# recordItem.pm
# sierraSpecialb.pm
# DBhandler.pm
# Loghandler.pm
# Mobiusutil.pm
# MARC::Record (from CPAN)
# 
# Blake Graham-Henderson 
# MOBIUS
# blake@mobiusconsortium.org
# 2013-1-24

 use lib qw(../);
 use strict; 
 use Loghandler;
 use Mobiusutil;
 use DBhandler;
 use recordItem;
 use sierraSpecialb;
 use Data::Dumper;
 use email;
 use DateTime;
 use utf8;
 use Encode;
 use DateTime::Format::Duration;

 my $barcodeCharacterAllowedInEmail=2000;
 
 #use warnings;
 #use diagnostics; 
		 
 my $configFile = @ARGV[0];
 if(!$configFile)
 {
	print "Please specify a config file\n";
	exit;
 }
 
 my $mobUtil = new Mobiusutil(); 
 my $conf = $mobUtil->readConfFile($configFile);
 
 if($conf)
 {
	my %conf = %{$conf};
	if ($conf{"logfile"})
	{
		my $log = new Loghandler($conf->{"logfile"});
		$log->addLogLine(" ---------------- Script Starting ---------------- ");
		my @reqs = ("dbhost","db","dbuser","dbpass","port","fileprefix","marcoutdir","school","alwaysemail","fromemail","ftplogin","ftppass","ftphost","queryfile","platform","pathtothis","maxdbconnections");
		my $valid = 1;
		for my $i (0..$#reqs)
		{
			if(!$conf{@reqs[$i]})
			{
				$log->addLogLine("Required configuration missing from conf file");
				$log->addLogLine(@reqs[$i]." required");
				$valid = 0;
			}
		}
		if($valid)
		{		
			my $pathtothis = $conf{"pathtothis"};
			my $maxdbconnections = $conf{"maxdbconnections"};
			my $queries = $mobUtil->readQueryFile($conf{"queryfile"});
			if($queries)
			{
				my %queries = %{$queries};
				
				my $school = $conf{"school"};
				my $type = @ARGV[1];
				if($type eq "thread")
				{
					thread(\%conf);
				}
				my $platform = $conf{"platform"};#ebsco or summon
				my $fileNamePrefix = $conf{"fileprefix"}."_cancels_";
				my $remoteDirectory = "/updates";
				if(defined($type))		
				{
					if($type eq "adds")
					{
						$valid = 1;
						$fileNamePrefix = $conf{"fileprefix"}."_updates_";
						if($platform eq 'ebsco')
						{
							$remoteDirectory = "/update";
						}
					}
					elsif(($platform eq 'summon') && ($type eq "cancels"))
					{
						$valid = 1;
						$remoteDirectory = "/deletes";
					}
					elsif($type eq "cancels")
					{
						$valid = 1;
						if($platform eq 'ebsco')
						{
							$remoteDirectory = "/update";
						}
					}
					elsif($type eq "full")
					{
						$valid = 1;
						$remoteDirectory = "/full";
						$fileNamePrefix = $conf{"fileprefix"}."_full_";
					}
					else
					{
						$valid = 0;
						print "You need to specify the type 'adds' or 'cancels' or 'full'\n";
					}
				}
				else
				{
					$valid = 0;
					print "You need to specify the type 'adds' or 'cancels'\n";
				}
				if(!defined($platform))
				{
					print "You need to specify the platform 'ebsco' or 'summon'\n";
				}
				else
				{
					$fileNamePrefix=$platform."_".$fileNamePrefix;
				}
				my @dbUsers = @{$mobUtil->makeArrayFromComma($conf{"dbuser"})};
				my @dbPasses = @{$mobUtil->makeArrayFromComma($conf{"dbpass"})};
				if(scalar @dbUsers != scalar @dbPasses)
				{
					print "Sorry, you need to provide DB usernames equal to the number of DB passwords\n";
					exit;
				}
				my $dbuser = @dbUsers[0];
				my $dbpass = @dbPasses[0];
			#All inputs are there and we can proceed
				if($valid)
				{
					my $dbHandler;
					my $failString = "Success";
					
					 eval{$dbHandler = new DBhandler($conf{"db"},$conf{"dbhost"},$dbuser,$dbpass,$conf{"port"});};
					 if ($@) {
						$log->addLogLine("Could not establish a connection to the database");
						$failString = "Could not establish a connection to the database";
						$valid = 0;
						my @tolist = ($conf{"alwaysemail"});
						my $email = new email($conf{"fromemail"},\@tolist,1,0,\%conf);
						$email->send("RMO $school - $platform $type FAILED - $failString","\r\n\r\nThis job is over.\r\n\r\n-MOBIUS Perl Squad-");						
						
					 }
					 if($valid)
					 {

						my $dt   = DateTime->now(time_zone => "local"); 	
						my $fdate = $dt->ymd;
						
						my $outputMarcFile = $mobUtil->chooseNewFileName($conf->{"marcoutdir"},$fileNamePrefix.$fdate,"mrc");
												
						if($outputMarcFile ne "0")
						{	
						#Logging and emailing
							$log->addLogLine("$school $platform $type *STARTING*");
							$dt    = DateTime->now(time_zone => "local");   # Stores current date and time as datetime object
							$fdate = $dt->ymd;   # Retrieves date as a string in 'yyyy-mm-dd' format
							my $ftime = $dt->hms;   # Retrieves time as a string in 'hh:mm:ss' format
							my $dateString = "$fdate $ftime";  # "2013-02-16 05:00:00";
							my @tolist = ($conf{"alwaysemail"});
							my $email = new email($conf{"fromemail"},\@tolist,0,0,\%conf);
							$email->send("RMO $school - $platform $type Winding Up - Job # $dateString","I have started this process.\r\n\r\nYou will be notified when I am finished\r\n\r\n-MOBIUS Perl Squad-");
						#Logging and emailing
						
		
							#print $outputMarcFile."\n";
							my $marcOutFile = $outputMarcFile;
							my $sierraSpecialb;
							$valid=1;
							my $selectQuery = $mobUtil->findQuery($dbHandler,$school,$platform,$type,$queries);
							
							#print "Path: $pathtothis\n";
							my $gatherTime = DateTime->now();
							local $@;
							eval{$sierraSpecialb = new sierraSpecialb($dbHandler,$log,$selectQuery,$type,$conf{"school"},$pathtothis,$configFile,$maxdbconnections);};
							if($@)
							{
								$valid=0;
								$email = new email($conf{"fromemail"},\@tolist,1,0,\%conf);
								$email->send("RMO $school - $platform $type FAILED - Job # $dateString","There was a failure when trying to get data from the database.\r\n\r\n I have only seen this in the case where an item has more than 1 bib and is in the same subset of records. Check the cron output for more information.\r\n\r\nThis job is over.\r\n\r\n-MOBIUS Perl Squad-\r\n\r\n$selectQuery");
								$log->addLogLine("Sierra scraping Failed. The cron standard output will have more clues.\r\n$selectQuery");
								$failString = "Scrape Fail";
							}
							
							my $recCount=0;
							my $format = DateTime::Format::Duration->new(
								pattern => '%M:%S' #%e days, %H hours,
							);
							my $gatherTime = $sierraSpecialb->calcTimeDiff($gatherTime);
							$gatherTime = $gatherTime / 60;
							#$gatherTime = $format->format_duration($gatherTime);
							my $afterProcess = DateTime->now(time_zone => "local");
							my $difference = $afterProcess - $dt;
							my $duration =  $format->format_duration($difference);
							my $extraInformationOutput = "";
							my $couldNotBeCut = "";
							my $rps;
							if($valid)
							{
								my @all = @{$sierraSpecialb->getAllMARC()};
								my @marc = @{@all[0]}; 
								my @tobig = @{$sierraSpecialb->getTooBigList()};
								$extraInformationOutput = @tobig[0];
								$couldNotBeCut = @tobig[1];
								my $marcout = new Loghandler($marcOutFile);
								$marcout->deleteFile();
								my $output;
								my $barcodes="";
								my @back = @{processMARC(\@marc,$platform,$type,$school,$marcout)};
								print Dumper(@back);
								$extraInformationOutput.=@back[0];
								$barcodes.=@back[1];
								$couldNotBeCut.=@back[2];
								$recCount+=@back[3];
								
								if(ref @all[1] eq 'ARRAY')
								{
									print "There were some files to process";
									my @dumpedFiles = @{@all[1]};
									foreach(@dumpedFiles)
									{	
										@marc =();
										my $marcfile = $_;
										my $check = new Loghandler($marcfile);
										if($check->fileExists())
										{
											my @file = @{$check->readFile()};
											push(@marc,@file);
											print "Read ".$#file." records from $marcfile\n";											
											$check->deleteFile();
											undef @file;
										}
										my @back = @{processMARC(\@marc,$platform,$type,$school,$marcout)};
										$extraInformationOutput.=@back[0];
										$barcodes.=@back[1];
										$couldNotBeCut.=@back[2];
										#print "Adding ".@back[3];
										$recCount+=@back[3];
									}
								}
								
								
								if(length($extraInformationOutput)>0)
								{
									$extraInformationOutput="These records were TRUNCATED due to the 100000 size limits: $extraInformationOutput \r\n\r\n";
								}
								if(length($couldNotBeCut)>0)
								{
									$couldNotBeCut="These records were OMITTED due to the 100000 size limits: $couldNotBeCut \r\n\r\n";
								}
								
								if($recCount>0)
								{	
									undef @marc;
									my @files = ($marcOutFile);
									if(0)  #switch FTP on and off easily
									{
										eval{$mobUtil->sendftp($conf{"ftphost"},$conf{"ftplogin"},$conf{"ftppass"},$remoteDirectory,\@files,$log);};
										 if ($@) 
										 {
											$log->addLogLine("FTP FAILED");
											$email = new email($conf{"fromemail"},\@tolist,1,0,\%conf);
											$email->send("RMO $school - $platform $type FTP FAIL - Job # $dateString","I'm just going to apologize right now, I could not FTP the file to ".$conf{"ftphost"}." ! Remote directory: $remoteDirectory\r\n\r\nYou are going to have to do it by hand. Bummer.\r\n\r\nCheck the log located: ".$conf{"logfile"}." and you will know more about why. Please fix this so that I can FTP the file in the future!\r\n\r\n File:\r\n\r\n$marcOutFile\r\n$recCount record(s).  \r\n\r\n-MOBIUS Perl Squad-");
											$failString = "FTP Fail";
											$valid=0;
										 }
									 }
								}
								else
								{
									$marcOutFile = "(none)";
								}
								if($valid)
								{
									my $extraBlurb="";
									if(($type eq "full") && ($platform eq "summon"))
									{
										$extraBlurb = "This is a new full catalog load for one of the following members of the MOBIUS consortium, Three Rivers Community College (ML6), William Jewel (MOI)l, University of Central Missouri (MCW), Missouri Southern State University (MOZ), Truman State University (TSU). Please refer to the Summon short name in the output file listed below and submit the request accordingly.\r\n\r\n";
									}
									$rps = $sierraSpecialb->getRPS();
									$afterProcess = DateTime->now(time_zone => "local");
									$difference = $afterProcess - $dt;
									$duration =  $format->format_duration($difference);
									$log->addLogLine("$school $platform $type: $marcOutFile");
									$log->addLogLine("$school $platform $type: $recCount Record(s)");
									$email = new email($conf{"fromemail"},\@tolist,0,1,\%conf);
									if($recCount>0)
									{	
										$marcOutFile = substr($marcOutFile,rindex($marcOutFile, '/')+1);
									}
									if(length($barcodes)>$barcodeCharacterAllowedInEmail)
									{
										$barcodes = substr($barcodes,0,$barcodeCharacterAllowedInEmail);
									}
									$email->send("RMO $school - $platform $type Success - Job # $dateString","$extraBlurb \r\nRecord gather duration: $gatherTime\r\nRecords per second: $rps\r\nTotal duration: $duration\r\n\r\nThis process finished without any errors!\r\n\r\nHere is some information:\r\n\r\nOutput File: \t\t$marcOutFile\r\n$recCount Record(s)\r\nFTP location: ".$conf{"ftphost"}."\r\nUserID: ".$conf{"ftplogin"}."\r\nFolder: $remoteDirectory\r\n\r\n$extraInformationOutput $couldNotBeCut -MOBIUS Perl Squad-\r\n\r\n$selectQuery\r\n\r\nThese are the top $barcodeCharacterAllowedInEmail characters included records:\r\n$barcodes");
								}
							}
				#OUTPUT TO THE CSV
							if($conf{"csvoutput"})
							{
								 my $csv = new Loghandler($conf{"csvoutput"});
								 my $csvline = "\"$dateString\",\"$school\",\"$platform\",\"$type\",\"$failString\",\"$marcOutFile\",\"$gatherTime\",\"$rps\",\"$duration\",\"$recCount Record(s)\",\"".$conf{"ftphost"}."\",\"".$conf{"ftplogin"}."\",\"$remoteDirectory\",\"$extraInformationOutput\",\"$couldNotBeCut\"";
								 $csvline=~s/\n//g;
								 $csvline=~s/\r//g;
								 $csvline=~s/\r\n//g;
								 
								 $csv->addLine($csvline);
								 undef $csv;
							 
							}
							
							$log->addLogLine("$school $platform $type *ENDING*");
						}
						else
						{
							$log->addLogLine("Output directory does not exist: ".$conf{"marcoutdir"});
						}
						
					 }
				 }
			 }
		 }
		 $log->addLogLine(" ---------------- Script Ending ---------------- ");
	}
	else
	{
		print "Config file does not define 'logfile'\n";		
	}
 }
 
 sub mbts856fix
 {
	my $marc = @_[0];
	my @t856 = $marc->field("856");
	
	foreach(@t856)
	{
		my $this856 = $_;
		my $z = $this856->subfield("z");
		if($z)
		{
			my $output = $this856->as_formatted();
			#print "Reading $output\n";
			$z = lc $z;			
			my $found = 0;
			if(index($z, "mbts electronic book") != -1)
			{
				$found = 1;
			}
			if(index($z, "freely available") != -1)
			{
				$found = 1;
			}
			if(index($z, "mbts") != -1)
			{
				$found = 1;
			}
			if(!$found)
			{
				$marc->delete_field($this856);
				my $output = $this856->as_formatted();
				print "Removing $output\n";
			}
		}
	}
	
	return $marc;
 }
 
 sub thread
 {
	my %conf = %{@_[0]};
	my $previousTime=DateTime->now;
	my $rangeWriter = new Loghandler("/tmp/rangepid.pid");
	my $mobUtil = new Mobiusutil();
	my $offset = @ARGV[2];
	my $increment = @ARGV[3];
	my $limit = $increment-$offset;
	my $pid = @ARGV[4];
	my $dbuser = @ARGV[5];
	my $typ = @ARGV[6];
	#print "Type = $typ\n";
	$rangeWriter->addLine("$offset $increment");
	#print "$pid: $offset - $increment $dbuser\n";
	my $dbpass = "";
	my @dbUsers = @{$mobUtil->makeArrayFromComma($conf{"dbuser"})};
	my @dbPasses = @{$mobUtil->makeArrayFromComma($conf{"dbpass"})};	
	my $i=0;
	foreach(@dbUsers)
	{
		if($dbuser eq $_)
		{
			$dbpass=@dbPasses[$i];
		}
		$i++;
	}
	my $pidWriter = new Loghandler($pid);
	$pidWriter->truncFile("0");	
	my $log = new Loghandler($conf->{"logfile"});
	my $pathtothis = $conf{"pathtothis"};
	my $queries = $mobUtil->readQueryFile($conf{"queryfile"});
	my $school = $conf{"school"};
	my $type = @ARGV[1];
	my $platform = $conf{"platform"};
	my $dbHandler;
	eval{$dbHandler = new DBhandler($conf{"db"},$conf{"dbhost"},$dbuser,$dbpass,$conf{"port"});};
	
	if ($@) {
		$pidWriter->truncFile("none\nnone\nnone\nnone\nnone\nnone\n$dbuser\nnone\n1\n$offset\n$increment");
		$rangeWriter->addLine("$offset $increment DEFUNCT");
		print "******************* I DIED DBHANDLER ********************** $pid\n";
	}
	else
	{
		my $dbHandler = new DBhandler($conf{"db"},$conf{"dbhost"},$dbuser,$dbpass,$conf{"port"});
		#print "Sending off to get thread query: $school, $platform, $type";
		my $selectQuery = $mobUtil->findQuery($dbHandler,$school,$platform,$typ,$queries);
		my $rang=" AND ID > $offset AND ID <= $increment";
		$selectQuery=~s/\$recordSearch/RECORD_ID/gi;
		$selectQuery=~s/\$rangestatement_id/ AND ID > $offset AND ID <= $increment/gi;
		$selectQuery=~s/\$rangestatement_ITEM_RECORD_ID/ AND ITEM_RECORD_ID > $offset AND ITEM_RECORD_ID <= $increment/gi;
		$selectQuery=~s/\$rangestatement_RECORD_ID/ AND RECORD_ID > $offset AND RECORD_ID <= $increment/gi;
		
		#$selectQuery.= " AND ID > $offset AND ID <= $increment";
		#print "Thread got this query\n\n$selectQuery\n\n";
		$pidWriter->truncFile("0");	
		#print "Thread started\n offset: $offset\n increment: $increment\n pidfile: $pid\n limit: $limit";
		my $sierraSpecialb;
		local $@;
		#print "Scraping:\n$dbHandler,$log,$selectQuery,$type,".$conf{"school"}.",$pathtothis,$configFile";
		eval{$sierraSpecialb = new sierraSpecialb($dbHandler,$log,$selectQuery,$type,$conf{"school"},$pathtothis,$configFile);};
		if($@)
		{
			#print "******************* I DIED SCRAPER ********************** $pid\n";
			$pidWriter->truncFile("none\nnone\nnone\nnone\nnone\nnone\n$dbuser\nnone\n1\n$offset\n$increment");
			$rangeWriter->addLine("$offset $increment DEFUNCT");
			exit;
		}
		my @diskDump = @{$sierraSpecialb->getDiskDump()};
		my $disk =@diskDump[0];
		my @marc =();
		my $check = new Loghandler($disk);
		my $recordCount = $sierraSpecialb->getRecordCount();
		if(!$check->fileExists())
		{
			$disk='';
			$recordCount=0;
			# print "fail\n";
				# $check->deleteFile();
				# $pidWriter->truncFile("none\nnone\nnone\nnone\nnone\nnone\n$dbuser\nnone\n1\n$offset\n$increment");
				# $rangeWriter->addLine("$offset $increment BAD OUTPUT".$check->getFileName()."\t".$@);
				# exit;
		}
		my @tobig = @{$sierraSpecialb->getTooBigList()};
		my $extraInformationOutput = @tobig[0];
		my $couldNotBeCut = @tobig[1];
		my $queryTime = $sierraSpecialb->getSpeed();
		my $secondsElapsed = $sierraSpecialb->calcTimeDiff($previousTime);
		#print "Writing to thread File:\n$disk\n$recordCount\n$extraInformationOutput\n$couldNotBeCut\n$queryTime\n$limit\n$dbuser\n$secondsElapsed\n";
		my $writeSuccess=0;
		my $trys=0;
		while(!$writeSuccess && $trys<100)
		{
			$writeSuccess = $pidWriter->truncFile("$disk\n$recordCount\n$extraInformationOutput\n$couldNotBeCut\n$queryTime\n$limit\n$dbuser\n$secondsElapsed");
			if(!$writeSuccess)
			{
				print "$pid -  Could not write final thread output, trying again: $trys\n";
			}
			$trys++;
		}
		
	}
	
	exit;
 }
 exit;