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
    test -n "$PARTITION" && local args=( -p $PARTITION )
    tcol=$(($(tput cols)-105))
    if test $tcol -gt 90; then
        tcol=90
    fi

    read -r -d '' SCRIPT <<'PERL'
        use Term::ANSIColor qw(color colored colorstrip);
        use Env;
        use List::Util qw(max);

        $counter++;
        BEGIN { 
            open $table, "|ccolumn -t" or die $!;
            $| = 1;
            $xsize=`tput lines`-1; 
            $size = $xsize;
            $all=0;
            $highp=0;
            $lowp=0;
            $other_run_total=0;
        };

        sub show {
            $_ =~ s/\b$USER\b/colored($USER, "bold magenta")/e;
            $_ =~ s/\bR\b/colored("R", "bold red")/e;
            chomp;
            $_ =~ s/\s+/\t/g;
            local $tabs = () = /\t/g;
            print $table color "bold" if $.==1;
            print $table $.>1?$.-1:"Rank", "\t";
            if ($tabs < 8) {
                $tabs++;
                s/\t([^\t]+)\s*$/\t...\t\1/;
            }
            print $table $_;
            print $table "\n";
            print $table color "reset" if $.==1;
            $found++;
        }

        $running = $F[4] eq "R";
        $pending = $F[4] eq "PD";
        $me = $F[3] eq $USER;
        $user = $F[3];
        $priority = $F[2] ne $LOWPRIORITY;
        $remaining = $size - $found - 12;

        if ($me) {
            if (not $priority) {
                $lowp++;
            } else {
                $highp++;
            }
            $all++;
            $running and $user_run_total++;
        } else {
            $running and $other_run_total++;
        };
        $running and $totals{$user}++;
        $pending and $pending{$user}++;
        $running and $anyrunning++;
        $running and $priority and $highp{$user}++;
        $pending and $priority and $highpp{$user}++;
        $size = $xsize - scalar(keys %totals) - scalar(keys %pending);
        (  $.<5 
           or ($me and ($running or $priority) and $user_run_total < 15 and $remaining > 7)
           or ($counter % $found eq 0 and $remaining > 20) 
           or ($user_run_total < 3 and $me and $running)
           or (not $me and $running and ($other_run_total<6 and $counter > 1 or $other_run_total<2))
        ) and $remaining > 2 and do {
            show;
            $counter=0;
            $clean=1;
            next;
        };
        $clean and do {
            show;
            print $table "...\t" for 1..8;
            print $table "...\n";
            $found++;
            $clean=0;
        };
        END {
            close $table;
            $, = " ";
            $\ = "\n";
            print;
            print color "bold";
            print "All", "jobs:", $.-1;
            print colored($USER, "bold magenta"), "jobs:", "$all";
            print colored($USER, "bold magenta"), "highprio:", $highp;
            print colored($USER, "bold magenta"), "lowprio:", $lowp;
            print color "reset";


            open $runfd, '>', \$runbuf;
            open $pendfd, '>', \$pendbuf;

            select $runfd;
            if ($totals{$USER}) {
                local $\ = undef;
                print colored($USER, "bold magenta"), "running:", $totals{$USER};
                print " " x (12-length($USER)-length($totals{$USER})),
                     "(highprio: $highp{$USER}/$totals{$USER})" if $highp{$USER};
                print "\n";
            } else {
                print colored($USER, "bold magenta"), "running:", 0;
            }

            for $i (sort { $totals{$b} <=> $totals{$a} } keys %totals) {
                if ($i ne $USER) {
                    local $\ = undef;
                    print $i, "running:", $totals{$i};
                    print " " x (12-length($i)-length($totals{$i})), 
                        "(highprio: $highp{$i}/$totals{$i})" if $highp{$i};
                    print "\n";
                }   
            };

            select $pendfd;
            if ($pending{$USER}) {
                local $\ = undef;
                print colored($USER, "bold magenta"), "pending:", $pending{$USER};
                print " " x (12-length($USER)-length($pending{$USER})), 
                    "(highprio: $highpp{$USER}/$pending{$USER})" if $highpp{$USER};
                print "\n";
            } else {
                print colored($USER, "bold magenta"), "pending:", "0";
            }
            for $i (sort { $pending{$b} <=> $pending{$a} } keys %pending) {
                if ($i ne $USER) {
                    local $\ = undef;
                    print $i, "pending:", $pending{$i} ;
                    print " " x (12-length($i)-length($pending{$i})), 
                        "(highprio: $highpp{$i}/$pending{$i})" if $highpp{$i};
                    print "\n";
                }
            }

            select STDOUT;

            @runq = split /\n/, $runbuf;
            @pendq = split /\n/, $pendbuf;
            $qlen = max $#runq, $#pendq;
            $maxlen = max(map { length colorstrip($_) } @runq);
            $maxlen += int max((`tput cols`-$maxlen-max(map { length colorstrip($_) } @pendq))/4, 1-$maxlen);
            for $i (0..$qlen) {
                $m = $maxlen + (length $runq[$i]) - (length colorstrip($runq[$i]));
                printf "%-${m}s  ", substr($runq[$i] // "", 0, $m);
                print $pendq[$i] // "";
            }
            
        }
PERL

    SQUEUE_FORMAT2="JobID:10 ,Name:20 ,QOS:15 ,UserName:8 ,StateCompact:3 ,TimeUsed:9 ,Tres:$tcol ,Reason:20" squeue "${args[@]}" | perl -ane "$SCRIPT" 
}

if [[ -t 0 ]]; then
    loop main
else
    main
fi

