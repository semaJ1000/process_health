#!/path/to/perl

package Process;
use v5.14;
use IDAS;
use Data::Dumper qw(Dumper);
use Time::Piece;
use Time::Seconds;

sub new{
   my ($class, $values) = @_;

   my $self = {
      # Set initial values to undefined. Important that they are defined in this
      # way so that eq and == can be used without error later.
      id => (defined $values->[0]) ? $values->[0] : "",
      path => (defined $values->[1]) ? $values->[1] : "",
      input => (defined $values->[2]) ? $values->[2] : "",
      output => (defined $values->[3]) ? $values->[3] : "",
      input_bool => (defined $values->[5]) ? $values->[5] : 0,
      output_bool => (defined $values->[6]) ? $values->[6] : 0,
      name => "",
      results => "",
      past_status => -1,
   };

   if ($self->{path}){
      # Take the last part of the process path as the process name.
      # ex: /path/to/process_health.pl -> process_health.pl
      ($self->{name}) = $self->{path} =~ m/\/([^\/]+)$/;
   }

   bless($self, $class);
   return $self;
}

# General getters and setters
sub set_id{
   my ($self, $id) = @_;
   $self->{id} = $id;
}

sub set_path{
   my ($self, $path) = @_;
   $self->{path} = $path;
}

sub set_input_path{
   my ($self, $input) = @_;
   $self->{path} = $input;
}

sub set_output_path{
   my ($self, $output) = @_;
   $self->{path} = $output;
}

sub set_input_bool{
   my ($self, $input_bool) = @_;
   $self->{path} = $input_bool;
}

sub set_output_bool{
   my ($self, $output_bool) = @_;
   $self->{path} = $output_bool;
}

sub get_name{
   my ($self) = @_;
   return $self->{name} if $self->{name};
   return ($self->{path} =~ m/\/([^\/]+)$/) ? $1 : 0 if $self->{path};
   return "No filename found";
}

sub get_id{
   my ($self) = @_;
   return $self->{id};
}

sub get_path{
   my ($self) = @_;
   return $self->{path};
}

sub get_results{
   my ($self) = @_;
   return $self->{results};
}

sub to_csv{
   # Transforms Process object to proper csv form for entry into
   # /path/to/process.csv
   my ($self) = @_;
   my $csv = $self->{id}.",".$self->{path}.",".$self->{input_path}.","
            .$self->{output_path}.",".$self->{input}.",".$self->{output};
   return $csv;
}

sub test_input{
   my ($self) = @_;
   my $status = 1;
   my $reason = "";
   my @reason = ();

   # Does the file exist
   if (!exists $self->{input}){
      $status = 0;
      $reason = "No input";
      push(@reason, $reason);
   }

   # Does the file contain anything
   if (!-s $self->{input}){
      $status = 0;
      $reason = "Input file is empty";
      push(@reason, $reason);
   }

   # Does the file have read permissions
   my $temp = $self->{path};
   my $ls = `ls -l $temp`;
   my $read_permission = $ls =~ m/^-r/;
   if (!$read_permission){
      $status = 0;
      $reason = "File does not have read permission";
      push(@reason, $reason);
   }

   # Check file type
   if (!$self->{input} =~ m/.txt$/){
      $status = 0;
      $reason = "Incorrect input file type";
      push(@reason, $reason);
   }

   return $status, @reason
}

sub test_output{
   my ($self) = @_;
   my $status = 1;
   my $reason = "";
   my @reason = ();
   my @file_info = stat($self->{output});
   my $last_updated_time = localtime($file_info[9]);
   my $yesterday = localtime() - ONE_DAY;
   my $last_hour = localtime() - ONE_HOUR;

   # Check if the file exists
   if (!exists $self->{output}){
      $status = 0;
      $reason = "No output";
      push(@reason, $reason);
   }

   # Check if the file is empty
   if (!-s $self->{output}){
      $status = 0;
      $reason = "Output file empty";
      push(@reason, $reason);
   }

   # Check if the file has write permissions
   my $temp = $self->{path};
   my $ls = `ls -l $temp`;
   my $write_permission = $ls =~ m/^-.w/;
   if (!$write_permission){
      $status = 0;
      $reason = "File does not have write permission";
      push(@reason, $reason);
   }

   # Check file type
   if (!$self->{input} =~ m/.txt$/){
      $status = 0;
      $reason = "Incorrect input file type";
      push(@reason, $reason);
   }

   if ($last_updated_time < $yesterday){
      $status = 0;
      $reason = "Output over a day old";
      push(@reason, $reason);
   }

   return $status, @reason;
}

sub execute_tests{
   my ($self) = @_;

   my $status = -1; # Default status
   my $reason = "No test types selected"; # Default reason
   my @result = ();
   my @reason = ();
   my $sike; # Variable to hold useless return

   if ($self->{input_bool} != 0){
      # ($status, $reason) = $self->test_input();
      ($status, @result) = $self->test_input();
      if (!$status){
         push(@reason, @result);
      }
   }
   if ($self->{output_bool} != 0){
      # ($status, $reason) = $self->test_output();
      ($status, @result) = $self->test_output() if $status;
      ($sike, @result) = $self->test_output() if !$status;
      if (!$status){
         push(@reason, @result);
      }
   }

   $reason = join("<br>", @reason);

   $reason = "Running Normally" if !$reason;


   if ($self->{past_status} == 1){
      if ($status){
         $self->{past_status} = $status;
      }
      else {
         $self->{past_status} = $status;
         $self->send_alert();
      }
   }
   else{
      $self->{past_status} = $status;
   }

   # $self->{results} = $self->{id}.",".$self->{name}.",".$status.",".$reason;
   $self->{results} = { id => $self->{id}, name => $self->{name}, status => $status, reason => $reason };
   return $status, $reason;
}

package Process_long; # 'is a'
#use base "Process";
our @ISA = qw(Process);
use v5.14;
use Data::Dumper qw(Dumper);
use Time::Piece;
use Time::Seconds;

sub new{
   my ($class, $values) = @_;

   my $self = {
      id => (defined $values->[0]) ? $values->[0] : "",
      path => (defined $values->[1]) ? $values->[1] : "",
      input => (defined $values->[2]) ? $values->[2] : "",
      output => (defined $values->[3]) ? $values->[3] : "",
      long_bool => (defined $values->[4]) ? $values->[4] : 0,
      input_bool => (defined $values->[5]) ? $values->[5] : 0,
      output_bool => (defined $values->[6]) ? $values->[6] : 0,
      name => "",
      results => "",
      past_status => -1,
   };

   ($self->{name}) = $self->{path} =~ m/\/([^\/]+)$/;

   bless($self, $class);
   return $self;
}

sub set_long_running_bool{
   my ($self, $long_bool) = @_;
   $self->{long_running} = @_;
}

sub set_none{
   my ($self) = @_;
   $self->{id} = "None";
   $self->{path} = "None";
   $self->{input} = "None";
   $self->{output} = "None";
   $self->{long_bool} = 0;
   $self->{input_bool} = 0;
   $self->{output_bool} = 0;
   $self->{name} = "None";
}

sub to_csv{
   my ($self) = @_;
   my $csv = $self->{id}.",".$self->{path}.",".$self->{input_path}.","
            .$self->{output_path}.",".$self->{long_running}.",".$self->{input}.",".$self->{output};
   return $csv;
}

sub test_long{
   my ($self) = @_;
   my $status = 1;
   my $reason = "";
   my @reason = ();

   my $command = `ps -e`;
   my ($name) = $self->{name};

   if (!($command =~ m/$name/)){
      $status = 0;
      $reason = "Program not running";
      push (@reason, $reason);
   }

   return $status, @reason;
}

sub test_output{
   my ($self) = @_;
   my $status = 1;
   my $reason = "";
   my @reason = ();
   my @file_info = stat($self->{output});
   my $last_updated_time = localtime($file_info[9]);
   my $yesterday = localtime() - ONE_DAY;
   my $last_hour = localtime() - ONE_HOUR;

   # Check if the file exists
   if (!exists $self->{output}){
      $status = 0;
      $reason = "No output";
      push(@reason, $reason);
   }

   # Check if the file is empty
   elsif (!-s $self->{output}){
      $status = 0;
      $reason = "Output file empty";
      push(@reason, $reason);
   }

   # Check if the file has write permissions
   my $temp = $self->{path};
   my $ls = `ls -l $temp`;
   my $write_permission = $ls =~ m/^-.w/;
   if (!$write_permission){
      $status = 0;
      $reason = "File does not have write permission";
      push(@reason, $reason);
   }

   # Check file type
   elsif (!$self->{input} =~ m/.txt$/){
      $status = 0;
      $reason = "Incorrect input file type";
      push(@reason, $reason);
   }

   # Check if output is too old
   elsif ($self->{output_bool} && $last_updated_time < $last_hour){
      $status = 0;
      $reason = "Long running script inactive for one hour";
      push(@reason, $reason);
   }

   # Check if output is too old
   elsif ($last_updated_time < $yesterday){
      $status = 0;
      $reason = "Output over a day old";
      push(@reason, $reason);
   }

   return $status, @reason;
}

sub execute_tests{
   my ($self) = @_;

   my $status = -1; # Default status
   my $reason = "No test types selected"; # Default reason
   my @result = ();
   my @reason = ();
   my $sike; # Variable to hold useless return


   if ($self->{input_bool} != 0){
      ($status, @result) = $self->test_input();
      if (!$status){
         push(@reason, @result);
      }
   }
   if ($self->{output_bool} != 0){
      ($status, @result) = $self->test_output() if $status;
      ($sike, @result) = $self->test_output() if !$status;
      if (!$status){
         push(@reason, @result);
      }
   }
      if ($self->{long_bool} != 0){
      ($status, @result) = $self->test_long() if $status;
      ($sike, @result) = $self->test_long() if !$status;
      if (!$status){
         push(@reason, @result);
      }
   }
   
   $reason = join("<br>", @reason);

   $reason = "Running Normally" if !$reason;

   $self->{results} = { id => $self->{id}, name => $self->{name}, status => $status, reason => $reason };
   return $status, $reason;
}

1;