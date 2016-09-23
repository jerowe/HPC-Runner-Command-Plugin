package HPC::Runner::Command::watch_db;

use MooseX::App::Command;
use Data::Dumper;
use Log::Log4perl qw(:easy);

extends 'HPC::Runner::Command';

command_short_description 'Watch the sqlitedb and exit when job submissions are complete.';
command_long_description 'Watch the sqlitedb for one or more submission ids. This is only really useful for testing. In a real world application it is probably best to just have the scheduler email you on completion, unless you are submitting more jobs than you want emails.';

has 'total_processes' => (
    traits  => ['Number'],
    is      => 'rw',
    isa     => 'Num',
    default => 0,
    handles => {
        set_total_processes => 'set',
        add_total_processes => 'add',
    },
);

option 'exit_on_fail' => (
    traits  => ['Bool'],
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
    documentation => 'Fail if any jobs have an exit code besides 0 - whether all tasks have completed or not',
);

option 'sleep_interval' => (
    is => 'rw',
    isa => 'Int',
    default => 30,
    documentation => 'Sleep interval in seconds to query sqlite db. For software testing you should leave as is. For longer running analyses you probably want to increase this.',
);

has 'log' => (
    is      => 'rw',
    default => sub {
        my $self = shift;

        Log::Log4perl->init( \ <<'EOT');
  log4perl.category = DEBUG, Screen
  log4perl.appender.Screen = \
      Log::Log4perl::Appender::ScreenColoredLevels
  log4perl.appender.Screen.layout = \
      Log::Log4perl::Layout::PatternLayout
  log4perl.appender.Screen.layout.ConversionPattern = \
      [%d] %m %n
EOT
        return get_logger();
        }

);

sub BUILD {
    my $self = shift;

    $self->gen_load_plugins;
    $self->job_load_plugins;
}

sub execute {
    my $self = shift;

    if($self->submission_id){
        $self->log->info("Watching Submission Id : " . $self->submission_id);
    }
    else{
        $self->log->info("No submission id specified. We will watch the whole database");
    }

    while (1){
        $self->query_submissions;
        sleep ($self->sleep_interval);
    }
}

sub query_task {
    my $self    = shift;
    my $task_rs = shift;

    #If exit on fail we don't care if we have completed the number of processes - just fail
    if ($self->exit_on_fail){
        $self->check_exit_code($task_rs);
    }

    if ($task_rs->count != $self->total_processes){
        #We have
        return;
    }
    elsif($task_rs->count == $self->total_processes){
        $self->log->info("We have completed ".$self->total_processes." tasks. Exiting successfully");
        exit 0;
    }

}

sub check_exit_code {
    my $self = shift;
    my $task_rs = shift;

    my $exit_codes = $task_rs->get_column('exit_code');

    while ( my $res = $task_rs->next ) {
        if ($res->exit_code != 0){
            $self->log->error("A task has failed! ".$res->task_pi);
            exit 1;
        }
    }
}

sub query_submissions {
    my $self = shift;

    my $results;

    if ($self->submission_id){
        $results = $self->schema->resultset('Submission')
            ->search( { 'submission_pi' => 1 } );
    }
    else{
        $results = $self->schema->resultset('Submission')
            ->search();
    }

    my $jobs  = $results->search_related('jobs');
    my $tasks = $jobs->search_related('tasks');

    while ( my $res = $results->next ) {
        $self->add_total_processes( $res->total_processes );
    }

    $self->query_job($jobs);

    $self->query_task($tasks);

}

#TODO To keep or not to keep?

sub query_job {
    my $self   = shift;
    my $job_rs = shift;

    #$job_rs->result_class('DBIx::Class::ResultClass::HashRefInflator');
    #while ( my $res = $job_rs->next ) {
        #print Dumper($res);
    #}
}

sub query_related {
    my $self = shift;

    #$ENV{DBIC_TRACE} = 1;

    $self->schema->storage->debug(1);

    my $results = $self->schema->resultset('Submission')
        ->search( {}, { 'prefetch' => { jobs => 'tasks' } } );

    $results->result_class('DBIx::Class::ResultClass::HashRefInflator');

    while ( my $res = $results->next ) {
        print "Here is a result!\n";
        print Dumper($res);
    }

}

1;
