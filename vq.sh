#!/bin/bash

# Author: Vivek Myers <vivek.myers@gmail.com>
# Date: 2025-01-09


function loop {
    (
        tput reset && tmp="$(mktemp)"  && trap 'rm -f "$tmp"' EXIT && while true
        do
            COLS=$(($(tput cols)-1))
            echo -n "" > "$tmp" && eval "$@" | for i in $(seq $(($(tput lines))))
            do
                IFS= read -r line
                printf "%.${COLS}s$(tput sgr0)\n" "$(printf "%-${COLS}s" "$line")" >> "$tmp"
            done && truncate -s -1 "$tmp" && tput cup 0 0 && cat "$tmp" && sleep 1 || break
        done
    )
}

function main {
    perl - <<'PERL'
        use Env;
        use List::Util qw(max);
        use Term::ANSIColor qw(color colored colorstrip);

        open $table, "| ccolumn -t" or die $!;
        @fmtfields = qw(JobID Name QOS UserName StateCompact TimeUsed Tres Reason);
        $sqarg = q(-O ') . join("###,", map {"$_:100"} @fmtfields) . q(');
        if (exists $ENV{PARTITION}) {
            $sqarg .=  qq( -p '$PARTITION');
        }
        open $squeue, "squeue ${sqarg} |" or die $!;

        $| = 1;
        $\ = "";
        $, = "";

        $total_mine = 0;
        $highp{$USER} = 0;
        $totals{$USER} = $user_run_total = 0;
        $pending{$USER} = 0;
        $highp = 0;
        $lowp = 0;
        $other_run_total = 0;

        $lines =`tput lines`-1;
        $size = $lines;
        $cols = `tput cols`;

        sub show {
            $spc = max(int($cols / 17) - 2, 5);

            $F{JOBID} = substr($F{JOBID}, 0, $spc);
            $F{NAME} = substr($F{NAME}, 0, 4*$spc);
            $F{REASON} = substr($F{REASON}, 0, 6*$spc) =~ s/\s//gr;
            $F{TIME} = substr($F{TIME}, 0, $spc);
            $F{TRES_ALLOC} = substr($F{TRES_ALLOC}, 0, 5*$spc);
            $F{QOS} = substr($F{QOS}, 0, $spc);
            $F{ST} = substr($F{ST}, 0, 2) =~ s/\bR\b/colored("R", "bold red")/er;
            $F{USER} = substr($F{USER}, 0, $spc) =~ s/\b$USER\b/colored($USER, "bold magenta")/er;;

            delete $F{JOBID} if $spc < 6;
            delete $F{TIME} if $spc < 6;
            delete $F{QOS} if $spc < 3;
            

            print color("bold"), "RANK" if $.==1;
            print $.-1 if $. > 1;
            print "\t";

            $_ = join("\t", @F{@fields});
            s/\s+/\t/g;
            s/^\s*|\s*$//g;

            $tabs =()= /\t/g;
            $_ .= "\t..." x (keys(%F)-$tabs-1) if $tabs-1 < $#fields;

            print;
            print "\n";
            print color "reset" if $.==1;

            $found++;
        }

        select $table;
        while(<$squeue>) {
            s/^\s+|\s+$//g;
            @F = split /\s*###\s*/;
            @fields = @F unless @fields;
            %F = map { $fields[$_] => $F[$_] } 0..$#F;

            $counter++;

            $running = $F{ST} eq "R";
            $pending = $F{ST} eq "PD";
            $user = $F{USER};
            $me = $user eq $ENV{USER};
            $priority = $F{QOS} ne $LOWPRIORITY;
            $remaining = $size - $found - 5;

            if ($running) {
                $F{TRES_ALLOC} =~ /gpu=(\d+)/ and $gpus{$user} += $1;
                $F{TRES_ALLOC} =~ /cpu=(\d+)/ and $cpus{$user} += $1;
            }
            
            if ($pending) {
                $F{TRES_ALLOC} =~ /gpu=(\d+)/ and $gpus_pending{$user} += $1;
                $F{TRES_ALLOC} =~ /cpu=(\d+)/ and $cpus_pending{$user} += $1;
            }

            $total_mine++ if $me;
            $running and $user_run_total++ if $me;
            $running and $other_run_total++ unless $me;

            $me and !$priority and $lowp++;
            $me and $priority and $highp++;

            $running and $totals{$user}++;
            $pending and $pending{$user}++;

            $running and $priority and $highp{$user}++;
            $pending and $priority and $highp_pending{$user}++;

            $size = $lines - scalar(keys %totals) - scalar(keys %pending);

            ( $.<5 or ($me and ($running or $priority) and $user_run_total < 15 and $remaining > 7)
                    or ($counter % $found eq 0 and $remaining > 20)
                    or ($user_run_total < 3 and $me and $running)
                    or (not $me and $running and ($other_run_total<6 and $counter > 1 or $other_run_total<2))
            ) and $remaining > 2 and do {
                show;
                $counter=0;
                $dotnext=1;
                next;
            };
            $dotnext and do {
                show;
                print "...\t" x ($tabs+1);
                print "...\n";
                $found++;
                $dotnext=0;
            };
        };

        close $table;

        select STDOUT;

        $, = " ";
        $\ = "\n";
        print;
        print color "bold";
        print "All", "jobs:", $.-1;
        print colored($USER, "bold magenta"), "jobs:", "$total_mine";
        print colored($USER, "bold magenta"), "high priority:", $highp;
        print colored($USER, "bold magenta"), "low priority:", $lowp;
        print color "reset";

        open $runfd, '>', \$runbuf;
        open $pendfd, '>', \$pendbuf;


        sub summarize {
            local $name = shift;
            local %val = %{shift()};
            local %highp = %{shift()};
            local %cpus = %{shift()};
            local %gpus = %{shift()};
            local @kv = keys %val;
            local @vv = values %val;
            local $w = width(\@kv) + width(\@vv);

            sub info {
                local $, = " ";
                local $\ = "\n";
                my $user = shift;
                my $color = shift;
                my %data;
                my $v = $val{$user};
                $data{cpus} = $cpus{$user} if $cpus{$user};
                $data{gpus} = $gpus{$user} if $gpus{$user};
                $data{highp} = $highp{$user}."/".$val{$user} if $highp{$user};
                $data{$_} = (" " x (3-length($_))).$data{$_} for keys %data;
                my $disp = $user;
                $disp = colored($user, $color) if $color;
                my $spc = " " x ($w - length($user) - length($v));
                print $disp, "$name: $v", $spc, keys %data ?
                    "(".join(", ", map {"$_=".$data{$_}} sort keys %data).")" : "";
            }

            info $USER, "bold magenta";

            for (sort { $val{$b} <=> $val{$a} } grep {$_ ne $USER} keys %val) {
                info $_;
            }
        }

        sub width {
            my $lines = shift;
            return max map { length colorstrip($_) } @$lines;
        }


        select $runfd;
        summarize("running",\%totals,\%highp,\%cpus,\%gpus);

        select $pendfd;
        summarize("pending",\%pending,\%highp_pending,\%cpus_pending,\%gpus_pending);

        select STDOUT;
        @runq = split /\n/, $runbuf;
        @pendq = split /\n/, $pendbuf;
        $qlen = max $#runq, $#pendq;
        $maxlen = width(\@runq);
        $maxlen += int max(($cols-$maxlen-width(\@pendq))/4, 1-$maxlen);
        for $i (0..$qlen) {
            $m = $maxlen + (length $runq[$i]) - (length colorstrip($runq[$i]));
            printf "%-${m}s  ", substr($runq[$i] // "", 0, $m);
            print $pendq[$i] // "";
        }
PERL

    }

    if [[ -t 0 ]]; then
        loop main
    else
        main
    fi

