#!/path/to/perl

=pod PHP
Long Running
Output: /path/to/middle_man.json
=cut PHP

# Library inclusions
use v5.14;
use lib'.';
use Objects;
use IDAS;
use JSON;
use POSIX ":sys_wait_h";
use Logger;
use Data::Dumper;
use File::Temp;
use Time::Piece;
use Time::Seconds;
use Fcntl qw(:flock);

my $IDAS = IDAS->new();
my $log = Logger->new();

# Global variable declaration
my $process_csv = '/path/to/process.csv'; 
my $process_json = '/path/to/middle_man.json';
my $email_path = '/path/to/email_list.txt';
my $website_url = 'http://webpage.net/path/to/front_end/main_page'; # CHANGE URL WHEN PUSHING TO PROD
my $updated_information = `ls -l $process_csv`;
my ($last_updated) = $updated_information =~ m/(\w{3} \d{2} (?:\d{2}:\d{2}|\d{4}))/; # Recognizes the form 'Mar 26 09:11' or 'Mar 26 2023' if it was last year
my @process_list; # Running list of all processes in the health page, used by update_csv
my @processes; # Also used by update_csv
my $status; # variable used to store the running status of the current process
my $reason; # variable used to store the explanation for the given status of the current process
my $parent_pid = $$; # Variable holding the pid of this (parent) process
my $child_count = 0; # Running count of how many child processes are running
my %process_status = (); # Hash to hold last recorded process status
my $scheduled_time; # Variable to hold Linux time for next daily task execution routine

sub check_for_update{
   # Subroutine checks last updated date on the csv file
   # If local information is behind the csv it will return true

   $log->logF("Checking for an update in the program list csv file");

   $updated_information = `ls -l $process_csv`;
   if (!$last_updated || $last_updated ne $updated_information){
      $last_updated = $updated_information;

      $log->logF("csv update found");

      return 1;
   }

   $log->logF("csv already up to date");

   return 0;
}

sub check_schedule{
   if ($scheduled_time < localtime){
      scheduler();
      return 1;
   }
   return 0;
}

sub scheduler{
   # Moves scheduled_time (Daily tasks) to the next day at 5 in the morning
   my $current_time = localtime;
   my $next_day = $current_time + ONE_DAY;
   my $next_execution = $next_day->truncate(to => 'day') + ONE_HOUR * 5;
   my $epoch_time = $next_execution->epoch;
   $scheduled_time = $epoch_time;
   $log->logF("Scheduler complete. Next execution of daily tasks set at: $next_execution");
}

sub restart{
   $log->logF("Restarting Script");
   # Check if the script is already being restarted
   my $restart_flag = shift @ARGV;
   # If the restart flag is set, do not restart again to avoid an infinite loop
   unless ($restart_flag) {
    # Restart the script
    exec $^X, $0, 'restart';
    exit;  # This line will not be reached if the script is successfully restarted
   }
}

sub do_daily_tasks{
   # Function executed once at 5:00 in the morning every day
   $log->logF("Beginning daily tasks");

   send_daily_mail();   # Send an alert counting how many processes are not running
   check_new_processes(); # Automated adding of any new processes that want to be tracked
   # restart();

   $log->logF("Finished daily tasks");
}

sub update_csv{
   # Subroutine that opens and reads the csv file and updates local
   # @process_list that contains all the process objects

   $log->logF("Updating csv");

   open(CSV, "<", $process_csv) || die "csv broken";
   my $csv = "id,address,input_path,output_path,long running,input,output\n";
   my $process;
   my $empty = 1;
   while (<CSV>){
      $empty = 0;
      if (!($_ =~ m/^\s*#/) && !($_ =~ m/^\s*$/)){ # ignore lines with a '#' at the start, or an empty line
         $csv .= $_;
      }
   }

   @process_list = (); # clear process list
   @processes = (); #clear processes to make room for update

   if ($empty){
      $log->logF("csv Empty");
      return;
   }

   @process_list = $IDAS->csv2list($csv);
   my $first = 0;
   my %new_hash = ();
   for my $entry (@process_list){
      # header layer in process csv, necessary to have an extra row or it will break
      next if !$first++;

      # Section to update the process status hash whenever an update happens to the csv
      my $cur_id = $entry->[0];
      if ($entry->[0] == $cur_id){
         $new_hash{$cur_id} = $process_status{$cur_id};
      }
      
      if ($entry->[4] == 1){
         $process = Process_long->new($entry);
      }
      else{
         $process = Process->new($entry);
      }
      push(@processes, $process);
   }
   %process_status = %new_hash;
   close(CSV);

   $log->logF("csv update done");

}

sub check_existence{
   # Function to make sure there can only ever be one parent process, never 2

   # Check to see if the process is running
      # If the process is running, terminate the running process and then continue
      # If the process is not running, continue as normal
   $log->logF("Checking if an instance of process health page is already running");
   my $process_name = "process_health.pl"; # NEED TO CHANGE THIS IF YOU CHANGE THE PROCESS NAME, NOT AUTOMATED MAYBE COULD AUTOMATE THIS
   my $pid = $$;
   my $found = 0;
   my $instance_string = `pgrep $process_name`;
   my @instances = split('\n', $instance_string);
   for my $instance (@instances){
      if ($instance != $pid){
         $found++;
         $log->logF("instance found, initiating termination");
         system("kill $instance");
         waitpid ($instance, 0);
         $log->logF("instance with pid $instance terminated");
      }
   }
   $log->logF("No instance found. Starting process_health.") if !$found;
}

sub send_alert{
   # Sends an email to each person on email list any time a process tracked by the page stops running
   my ($id) = @_;
   $log->logF("Process with id $id stopped running. Sending alert.");
   open(EMAIL,'<',$email_path);
   while (my $line = <EMAIL>){
      chomp($line);
      if ($line){
         my $email = $line;
         $IDAS->sendMail(Subject => 'PHP Alert'
                        ,To => $email
                        ,From => 'Process Health Page'
                        ,Body => 'Process with id '.$id.' has stopped running. '
                                 .'Please visit '.$website_url.' to see more.'
                        );
      }
   }
   close(EMAIL);
   $log->logF("Alert sent");
}

sub send_daily_mail{
   # Sends an email to each person on email list outlining how many tracked processes are running or not
   my $working_count = 0;
   my $fail_count = 0;
   for my $key (keys %process_status){
      $working_count++ if $process_status{$key};
      $fail_count++ if !$process_status{$key};
   }
   open(EMAIL,'<',$email_path);
   while (my $line = <EMAIL>){
      chomp($line);
      if ($line){
         my $email = $line;
         $IDAS->sendMail(Subject => 'Daily PHP Alert'
                        ,To => $email
                        ,From => 'Process Health Page'
                        ,Body => 'There are '.$working_count.' processes running properly '
                                 .'and '.$fail_count.' processes not running. '
                                 .'Please visit '.$website_url.' to see more.'
                        );
      }
   }
   close(EMAIL);
   $log->logF("Daily report sent");
}

sub pid_to_working_dir{
   # Takes a process pid as input and returns the full file path
   my ($pid) = @_;
   my $working_dir = `pwdx 2>/dev/null $pid`;
   return 0 if !$working_dir;
   chomp($working_dir);
   $working_dir =~ s/^\d*:\s*//;
   $working_dir =~ s/\0//g;
   my $cmdline = `cat /proc/$pid/cmdline`;
   my ($name) = $cmdline =~ m{([^/]+)$};
   $name =~ s/\0//g;
   return 0 if $name =~ m/-bash/;
   my $full_path = $working_dir."/".$name;
   return $full_path;
}

sub check_new_processes{
   # Function to automate adding of processes to the health page
   $log->logF("Checking for new processes to add to process health page");
   my $ps = `ps -e -o pid=`;
   my @pids = split("\n", $ps);
   $log->logF("%d process pids found in 'ps -e -o pid='", scalar(@pids));
   my @file_paths = ();
   for my $pid (@pids){
      $pid =~ s/^\s*//;
      my $path = pid_to_working_dir($pid);
      push(@file_paths, $path) if $path;
   }
   $log->logF("%d file paths found using pwdx and cat /proc/pid/cmdline", scalar(@file_paths));
   my @new_processes;
   my $pod_mode = 0;
   for my $path (@file_paths){
      next if $path =~ m/\0(?!$)/;
      open(FILE, '<', $path) or $log->logF("Failed to open file with path $path") and next;
      my %process = (
         id => "None",
         path => $path,
         input_path => "None",
         output_path => "None",
         long_running => 0,
         input => 0,
         output => 0,
      );
      while (my $line = <FILE>){
         if($pod_mode == 1){
            if($line =~ m/[iI]nput: (.+)$/){
               $process{input_path} = $1;
               $process{input} = 1;
            }
            elsif($line =~ m/[oO]utput: (.+)$/){
               $process{output_path} = $1;
               $process{output} = 1;
            }
            elsif($line =~ m/[lL]ong [rR]unning$/){
               $process{long_running} = 1;
            }
         }
         if ($line =~ m/=pod PHP/){
            $pod_mode = 1;
            next;
         }
         elsif ($line =~ m/=cut PHP/){
            $pod_mode = 0;
            last;
         }
         else{
            next;
         }
      }
      close(FILE);
      my $process = "#,".$process{path}.",".$process{input_path}.",".$process{output_path}.",".$process{long_running}.",".$process{input}.",".$process{output};
      push(@new_processes, $process);
   }
   $log->logF("%d process csv's created", scalar(@new_processes));

   # At this point we have @new_processes filled with each process_csv that has been found
   open (CSV,"+<",$process_csv);
   my $cur_id;
   my $max_id = -1;
   my $first = 1;
   while (my $line = <CSV>){
      if ($first){
         $first-- and next;
      }
      chomp($line);
      $cur_id = (split(',', $line))[0];
      $max_id = $cur_id if $cur_id > $max_id;
      for(my $i = 0; $i < scalar(@new_processes); $i++){
         $new_processes[$i] =~ s/^[^,]+/$cur_id/;
         if ($new_processes[$i] eq $line){
            splice(@new_processes,$i,scalar(@new_processes));
         }
      }
   }
   for my $process (@new_processes){
      print CSV "\n";
      $max_id++;
      $max_id++ while $max_id < 1;
      $process =~ s/^[^,]+/$max_id/;
      print CSV $process;
   }
   close(CSV);
   $log->logF("%d new processes added to the process health page", scalar(@new_processes));
}

sub handle_signal{
   # Function is called every time a child process dies
   $child_count--;
}
sub last_words_INT{
   $log->logF("Program with pid $parent_pid terminating due to SIGINT");
   exit;
}
sub last_words_TERM{
   $log->logF("Program with pid $parent_pid terminating due to SIGTERM");
   exit;
}
sub last_words_HUP{
   $log->logF("Program with pid $parent_pid terminating due to SIGHUP");
   exit;
}
sub last_words_QUIT{
   $log->logF("Program with pid $parent_pid terminating due to SIGQUIT");
   exit;
}

$SIG{'USR1'} = sub { handle_signal() };   # Signal handler is executed every time 'USR1' signal is recieved from a child process
$SIG{INT} = sub { last_words_INT() };
$SIG{TERM} = sub { last_words_TERM() };
$SIG{HUP}  = sub { last_words_HUP() };
$SIG{QUIT} = sub { last_words_QUIT() };

$log->logF("Starting process health. Running startup tasks.");
check_existence(); # ensure only one running instance
$log->logF("Scheduling first execution time of daily tasks");
scheduler(); # Initialize schedule
$log->logF("Initializing a process csv to keep track of all the processes that need to be displayed on the webpage");
update_csv(); # initialize csv

check_new_processes();

# Application Loop
for(;;){
   $log->logF("Top of application loop");
   if (check_for_update()){
      update_csv();
   }
   if (check_schedule){
      do_daily_tasks();
   }

   my @temp_files; # array to hold references to all temporary files used by the child processes
   my @child_pids; # array to keep track of all child pids in the parent process

   my $num_processes = scalar(@processes);
   $log->logF("Starting children to test $num_processes processes in the process csv");
   for my $process (@processes){
      1 while $child_count > 4;  # Loop to ensure there are never more than 5 child processes

      my $temp_file = File::Temp->new(UNLINK => 1); # creates a temporary file that will be destroyed when it is closed
      push @temp_files, $temp_file;
      $child_count++;
      my $pid = fork();
      die "failed fork" unless defined $pid;

      if($pid){   # in parent
         push @child_pids, $pid;
         next;
      }
      else{       # in child
         my $name = $process->get_name();
         ($status, $reason) = $process->execute_tests();

         my $results = $process->get_results();
         open my $fh, '>', $temp_file or die "Cannot open file: $!";
         $Data::Dumper::Terse = 1;     # Removes the $var1 from the beginning of the Data::Dumper dump
         print $fh Dumper($results);
         $Data::Dumper::Terse = 0;

         system("kill -USR1 $parent_pid");   # Send a signal to the parent telling it the child has ended

         my $exit_status = $process->get_id().$status;
         exit $exit_status; # Sends back ID + Status to parent
      }
   }

   for my $pid (@child_pids){
      my $return = waitpid ($pid, 0);
      my $child_status = $?;
      my $exit_code = $child_status >> 8; # Determine true exit code from the child return value
      my ($id) = $exit_code =~ m/^(\d+)\d$/;
      my ($status) = $exit_code =~ m/^\d+(\d)$/;

      if (!defined $process_status{$id} || !exists $process_status{$id}){ # Fill process_status array
         $process_status{$id} = $status;
      }
      else{
         if ($process_status{$id} == 1 && $status == 0){
            $process_status{$id} = $status;
            send_alert($id);
         }
         else{
            $process_status{$id} = $status;
         }
      }
      $log->logF("Child finished testing process with id: $id status: $status");
   }

   my @hash_array;
   $log->logF("Reading information from temp files created by child processes");
   for my $temp_file (@temp_files){
      open my $fh, '<', $temp_file;
      local $/;
      my $serialized_data = <$fh>; # Read all process data from temp file
      close $fh;
      my $hash_ref = eval $serialized_data;
      push @hash_array, $hash_ref;
   }

   $log->logF("Shifting process information to json format");
   my $json = to_json(\@hash_array, { pretty => 1 });

   open(JSON, ">", $process_json) or die "Cannot open file";
   flock(JSON, LOCK_EX) or die "Cannot lock file - $!\n";

   $log->logF("Writing json information to the json file");
   print JSON $json;

   flock(JSON, LOCK_UN) or die "Cannot unlock file $!\n";
   close(JSON);

   $log->logF("Bottom of application loop");
   $log->logF("");
   sleep(5);
}

1;