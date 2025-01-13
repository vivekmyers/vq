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
    our (%F, $tabs, $found, @fields, $cols);
    local ($\, $,) = undef;
    local $spc = max( int( $cols / 17 ) - 2, 5 );

    sub trunc {
        my ($k, $n) = @_;
        $s = int ($spc * $n);
        $F{$k} = sprintf "%-${s}s", substr( $F{$k}, 0, $s );
    }

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

    $F{ST} = substr( $F{ST}, 0, 2 ) =~ s/\bR\b/colored("R", "bold red")/er;
    $F{USER} =~ s/\b$USER\b/colored($USER, "bold magenta")/e;

    delete $F{JOBID} if $spc < 6;
    delete $F{TIME} if $spc < 6;
    delete $F{QOS} if $spc < 3;

    print color("bold") if $. == 1;

    $_ = join( "\t", @F{@fields} );

    $tabs =()= /\t/g;
    $_ .= "\t..." x ( keys(%F) - $tabs - 1 ) if $tabs - 1 < $#fields;

    print;
    print "\n";
    print color "reset" if $. == 1;

    $found++;
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
    local %highp = %{ shift() };
    local %cpus = %{ shift() };
    local %gpus = %{ shift() };

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
        $data{cpus} = $cpus{$user} if $cpus{$user};
        $data{gpus} = $gpus{$user} if $gpus{$user};
        $data{highp} = $highp{$user} . "/" . $val{$user} if $highp{$user};
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


system "tput reset";

for ( ;; ) {
    system "tput cup 0 0";

    my (%highp, %highp_pending, %totals, %pending, %gpus, %cpus, %gpus_pending, %cpus_pending);

    my ($all, $total_mine, $highp, $user_run_total, $lowp, $other_run_total) = (0) x 6;

    $totals{$USER} = $pending{$USER} = $highp{$USER} = 0;

    local ($tabs, $counter, $found, $dotnext, $lines, $cols) = (0) x 6;
    local @fields;

    local $lines = my $size = int `tput lines` - 1;
    local $cols = int(`tput cols`) - 1;

    open my $squeue, "squeue ${sqarg} |" or die $!;

    open my $outfd, ">", \my $outbuf;
    select $outfd;

    while (<$squeue>) {
        $all++ if @fields;

        s/^\s+|\s+$//g;
        local @F = split /\s*###\s*/;
        unshift @F, "RANK" if $. == 1;
        unshift @F, $. - 1 if $. > 1;

        @fields = @F unless @fields;
        local %F = map { $fields[$_] => $F[$_] } 0 .. $#F;

        $counter++;

        my $running = $F{ST} eq "R";
        my $pending = $F{ST} eq "PD";
        my $user = $F{USER};
        my $me = $user eq $ENV{USER};
        my $priority = getprio $F{QOS};
        my $remaining = $size - $found;

        if ($running) {
            $F{TRES_ALLOC} =~ /gpu=(\d+)/ and $gpus{$user} += $1;
            $F{TRES_ALLOC} =~ /cpu=(\d+)/ and $cpus{$user} += $1;
        }

        if ($pending) {
            $F{TRES_ALLOC} =~ /gpu=(\d+)/ and $gpus_pending{$user} += $1;
            $F{TRES_ALLOC} =~ /cpu=(\d+)/ and $cpus_pending{$user} += $1;
        }

        $total_mine++ if $me;
        $running and $other_run_total++ unless $me;

        $me and !$priority and $lowp++;
        $me and $priority and $highp++;

        $running and $totals{$user}++;
        $pending and $pending{$user}++;

        $running and $priority and $highp{$user}++;
        $pending and $priority and $highp_pending{$user}++;

        $size = $lines - max( scalar( keys %totals ), scalar( keys %pending )) - 7;

        ( $. < 5
            or ( $me
                 and ( $running or $priority and $highp < 10 )
                 and $user_run_total < 15
                 and $remaining > 7 )
            or ( $counter % $found eq 0 and $remaining > 20 )
            or ( $user_run_total < 3 and $me and $running )
            or ( not $me
                 and $running
                 and ( $other_run_total < 6 and $counter > 1
                        or $other_run_total < 2 )
            )
        ) and $remaining > 2 and do {
            $running and $user_run_total++ if $me;
            show;
            $counter = 0;
            $dotnext = 1;
            next;
        };
        $dotnext and do {
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
    print "All jobs:", $all;
    print colored( $USER, "bold magenta" ), "jobs:", "$total_mine";
    print colored( $USER, "bold magenta" ), "high priority:", $highp;
    print colored( $USER, "bold magenta" ), "low priority:", $lowp;
    print color "reset";

    open my $runfd, '>', \my $runbuf;
    open my $pendfd, '>', \my $pendbuf;

    select $runfd;
    summarize "running", \%totals, \%highp, \%cpus, \%gpus ;

    select $pendfd;
    summarize "pending", \%pending, \%highp_pending, \%cpus_pending, \%gpus_pending;

    select $outfd;
    my @runq = split /\n/, $runbuf;
    my @pendq = split /\n/, $pendbuf;
    my $qlen = max $#runq, $#pendq;
    my $maxlen = width( \@runq );
    $maxlen += int max( ( $cols - $maxlen - width( \@pendq ) ) / 4, 1 - $maxlen );

    for $i ( 0 .. $qlen ) {
        my $m = $maxlen + ( length $runq[$i] ) - ( length colorstrip( $runq[$i] // "" ) );
        printf "%-${m}s ", substr( $runq[$i] // "", 0, $m );
        print $pendq[$i] // "";
    }

    select STDOUT;
    my @outbuf = split /\n/, $outbuf;
    my $sgr = color "reset";
    for (@outbuf) {
        chomp;
        s/\t/  /g;
        my $m = $cols + ( length $_ ) - ( length colorstrip $_ );
        printf "%-${m}s", substr($_, 0, $m);
        print $sgr;
    }

    my $clines = $lines - $found - 2 - $#outbuf;
    print (" " x $cols) for 1 .. $clines;

    if ( !-t STDOUT ) {
        last;
    }

    sleep 1;
}
