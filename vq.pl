#!/usr/bin/env perl

# Author: Vivek Myers <vivek.myers@gmail.com>
# Date: 2025-01-09

use Env;
use List::Util qw(max);
use Term::ANSIColor qw(color colored colorstrip);

my @fmtfields = qw(JobID Name QOS UserName StateCompact TimeUsed Tres Reason);
my $sqarg = q(-O ') . join( "###,", map {"$_:100"} @fmtfields ) . q(');
if ( exists $ENV{PARTITION} ) {
    $sqarg .= qq( -p '$PARTITION');
}

$|++;
$\ = undef;
$, = undef;

sub show {
    our (%F, $tabs, $lines_printed, @fields, $cols);
    local ($\, $,) = undef;
    local $spc = max( int( $cols / 17 ) - 2, 5 );

    sub trunc {
        my ($k, $n) = @_;
        $s = int ($spc * $n);
        $F{$k} = sprintf "%-${s}s", substr( $F{$k}, 0, $s );
    }

    my $isrunning = $F{ST} eq "R";
    my $isme = $F{USER} eq $ENV{USER};

    $F{REASON} =~ s/,\s+/,/g;
    $F{REASON} =~ s/\w\K\s+/-/g;

    trunc "JOBID", 1;
    trunc "NAME", 4;
    trunc "REASON", 6;
    trunc "TIME", 1.5;
    trunc "TRES_ALLOC", 5;
    trunc "QOS", 1.5;
    trunc "ST", 3 / $spc;
    trunc "USER", 1;
    trunc "RANK", 4 / $spc;

    $F{ST} = substr( $F{ST}, 0, 2 );
    $F{ST} = colored( $F{ST}, "bold red" ) if $isrunning;
    $F{USER} = colored( $F{USER}, "bold magenta" ) if $isme;

    delete $F{JOBID} if $spc < 6;
    delete $F{TIME} if $spc < 6;
    delete $F{QOS} if $spc < 3;

    print color("bold") if $. == 1;

    $_ = join( "\t", @F{@fields} );

    $tabs =()= /\t/g;
    $_ .= "\t..." x ( keys(%F) - $tabs - 1 ) if $tabs - 1 < $#fields;

    print;
    print "\n";
    print color("reset") if $. == 1;

    $lines_printed++;
}

sub getprio {
    my $qos = shift;
    if ( exists $ENV{PRIORITY} ) {
        return $qos =~ /$ENV{PRIORITY}/;
    }
    elsif ( exists $ENV{LOWPRIORITY} ) {
        return $qos !~ /$ENV{LOWPRIORITY}/;
    }
    else {
        return $qos =~ /high/;
    }
}

sub summarize {
    local $name = shift;
    local %val = %{ shift() };
    local %highp_running = %{ shift() };
    local %cpus_running = %{ shift() };
    local %gpus_running = %{ shift() };

    my @kv = keys %val;
    my @vv = values %val;
    local $w = width( \@kv ) + width( \@vv );

    sub info {
        local $, = " ";
        local $\ = "\n";
        my $user = shift;
        my $color = shift;
        my %data;
        my $v = $val{$user};
        $data{cpus} = $cpus_running{$user} if $cpus_running{$user};
        $data{gpus} = $gpus_running{$user} if $gpus_running{$user};
        $data{highp} = $highp_running{$user} . "/" . $val{$user} if $highp_running{$user};
        $data{$_} = ( " " x ( 3 - length($_) ) ) . $data{$_}
        for keys %data;
        my $disp = $user;
        $disp = colored( $user, $color ) if $color;
        my $spc = " " x ( $w - length($user) - length($v) );
        print $disp, "$name: $v", $spc,
            keys %data ?
            "(" . join( ", ", map { "$_=" . $data{$_} } sort keys %data ) . ")" : "";
    }

    info $USER, "bold magenta";

    for ( sort { ( $val{$b} <=> $val{$a} ) or ( $a cmp $b ) }
        grep { $_ ne $USER } keys %val) { info $_; }
}

sub width {
    my $lines = shift;
    return max map { length colorstrip($_) } @$lines;
}

sub colorwidth {
    local $_ = shift // $_;
    return 0 unless length();
    return length() - length colorstrip($_);
}


system "tput reset";

for ( ;; ) {
    print " " x $cols for 1..3;
    system "tput cup 0 0";

    my (%highp_running, %highp_pending, %running, %pending,
        %gpus_running, %cpus_running, %gpus_pending, %cpus_pending);

    my ($all_jobs, $total_mine, $highp, $lowp, $other_run_total) = (0) x 5;

    $running{$USER} = $pending{$USER} = $highp_running{$USER} = 0;

    local ($tabs, $counter, $lines_printed, $dotnext) = (0) x 4;
    local @fields;

    local $lines = int `tput lines` - 1;
    local $cols = int(`tput cols`);

    open my $squeue, "squeue ${sqarg} |" or die $!;

    open my $outfd, ">", \my $outbuf;
    select $outfd;

    while (<$squeue>) {
        $all_jobs++ if @fields;

        s/^\s+|\s+$//g;
        local @F = split /\s*###\s*/;
        unshift @F, "RANK" if $. == 1;
        unshift @F, $. - 1 if $. > 1;

        @fields = @F unless @fields;
        local %F = map { $fields[$_] => $F[$_] } 0 .. $#F;

        $counter++;

        my $isrunning = $F{ST} eq "R";
        my $ispending = $F{ST} eq "PD";
        my $user = $F{USER};
        my $me = $user eq $ENV{USER};
        my $priority = getprio $F{QOS};

        if ($isrunning) {
            $F{TRES_ALLOC} =~ /gpu=(\d+)/ and $gpus_running{$user} += $1;
            $F{TRES_ALLOC} =~ /cpu=(\d+)/ and $cpus_running{$user} += $1;
        }

        if ($ispending) {
            $F{TRES_ALLOC} =~ /gpu=(\d+)/ and $gpus_pending{$user} += $1;
            $F{TRES_ALLOC} =~ /cpu=(\d+)/ and $cpus_pending{$user} += $1;
        }

        $total_mine++ if $me;
        $isrunning and $other_run_total++ unless $me;

        $me and !$priority and $lowp++;
        $me and $priority and $highp++;

        $isrunning and $running{$user}++;
        $ispending and $pending{$user}++;

        $isrunning and $priority and $highp_running{$user}++;
        $ispending and $priority and $highp_pending{$user}++;

        my $remaining = $lines - max( scalar( keys %running ), scalar( keys %pending )) - $lines_printed - 8;

        if (
            ( $. < 5
                or ( $me and ( $isrunning or $priority and $highp < 10 )
                         and $user_run_total < 15
                         and $remaining > 7 )
                or ( $counter % $lines_printed eq 0 and $remaining > 20 )
                or ( not $me and $isrunning
                             and ( $other_run_total < 6 and $counter > 1
                                                        or $other_run_total < 2 )
                )
            ) and $remaining > 7 or (
                $running{$USER} < 3 and $me and $isrunning and $remaining > 2
            ) or (
                $pending{$USER} < 3 and $me and $ispending and $remaining > 2
            )
        ) {
            show;
            $counter = 0;
            $dotnext = 1;
            next;
        };
        if ($dotnext) {
            show;
            %F = map { $fields[$_] => "..." } 0 .. $#F;
            show;
            $dotnext = 0;
        };
    }

    close $squeue;
    $? and die "squeue failed ($?)";

    local $, = " ";
    local $\ = "\n";

    print;
    print color "bold";
    print "All jobs:", $all_jobs;
    print colored( $USER, "bold magenta" ), "jobs:", "$total_mine";
    print colored( $USER, "bold magenta" ), "high priority:", $highp;
    print colored( $USER, "bold magenta" ), "low priority:", $lowp;
    print color "reset";

    open my $runfd, '>', \my $runbuf;
    open my $pendfd, '>', \my $pendbuf;

    select $runfd;
    summarize "running", \%running, \%highp_running, \%cpus_running, \%gpus_running ;

    select $pendfd;
    summarize "pending", \%pending, \%highp_pending, \%cpus_pending, \%gpus_pending;

    select $outfd;
    my @runq = split /\n/, $runbuf;
    my @pendq = split /\n/, $pendbuf;
    my $qlen = max $#runq, $#pendq;
    my $maxlen = width( \@runq );
    $maxlen += int max( ( $cols - $maxlen - width( \@pendq ) ) / 4, 1 - $maxlen );

    for $i ( 0 .. $qlen ) {
        my $m = $maxlen - 6 + colorwidth $runq[$i];
        printf "%-${m}s%s", substr( $runq[$i] // "", 0, $m ), " "x4;
        print $pendq[$i] // "";
    }

    select STDOUT;
    my @outbuf = split /\n/, $outbuf;
    for (@outbuf) {
        chomp;
        s/\t/  /g;
        my $m = $cols + colorwidth();
        printf "%-${m}s", substr($_, 0, $m);
        print color "reset";
    }

    my $extra_lines = $lines - $lines_printed - 2 - $#outbuf;
    print (" " x $cols) for 1 .. $extra_lines;

    if ( !-t STDOUT ) {
        last;
    }

    sleep 1;
}
