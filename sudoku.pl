#!/usr/bin/env perl6

# A unfilled cell is never equal to any value
multi compare-cell(Array $other, Int $this) {
    return 0;
}
multi compare-cell(Int $other, Int $this) {
    return $other == $this;
}

sub cleanup-impossible-values($sudoku, Int $level = 1) {
    my Bool $resolved;
    repeat {
        $resolved = False;
        for 0..2 X 0..2 X 0..2 X 0..2 -> int $sx, int $sy, int $x, int $y {
            if ($sudoku[$x+3*$sx][$y+3*$sy] ~~ Array) {
                # impossible values are the values listed as possible but that
                # actually are already assigned...
                # for all the possible values
                $sudoku[$x+3*$sx][$y+3*$sy] = [
                    grep { !compare-cell($sudoku[any(0..2)+3*$sx][any(0..2)+3*$sy], $_) },
                    grep { !compare-cell($sudoku[any(0..8)][$y+3*$sy], $_)  },
                    grep { !compare-cell($sudoku[$x+3*$sx][any(0..8)], $_) },
                    @($sudoku[$x+3*$sx][$y+3*$sy]);
                    ];
                if ($sudoku[$x+3*$sx][$y+3*$sy].elems == 1) {
                    # if only one element is left, then make it resolved
                    #say '.' x $level ~ (1+$x+3*$sx)~" "~(1+$y+3*$sy)~" solved...";
                    $sudoku[$x+3*$sx][$y+3*$sy] =
                        $sudoku[$x+3*$sx][$y+3*$sy].shift;
                    $resolved = True;
                } elsif ($sudoku[$x+3*$sx][$y+3*$sy].elems == 0) {
                    #say '.' x $level ~ (1+$x+3*$sx)~" "~(1+$y+3*$sy)~" Invalid solution...";
                    #print-sudoku($sudoku,$level);
                    return 0;
                }
            }
        }
    } while $resolved;
    return 1;
}

sub try-value($sudoku, Int $x, Int $y, Int $val, Int $level = 1) {
    my $solution = clone-sudoku($sudoku);
    $solution[$x][$y] = $val;
    #print-sudoku($solution,$level);
    my $solved = solve-sudoku($solution, $level);
    if $solved {
        return $solved;
    } else {
        return 0;
    }
}

# Functions to find out which cell to try solving first
multi cell-cost(Array $val) {
    return $val.elems;
}
multi cell-cost(Int $val) {
    return 1;
}
sub cell-cost-wrapper($sudoku, Array $val) {
    my ($x, $y) = @($val);
    # try to solve first the cells with the least amount of choices in
    # the section with the least amount of choices.
    my $this_cell_cost = cell-cost($sudoku[$x][$y]);
    my $this_section_cost = 0;
    my $sx = Int($x / 3);
    my $sy = Int($y / 3);
    for 0..2 X 0..2 -> $lx, $ly {
        $this_section_cost += cell-cost($sudoku[$lx+$sx*3][$ly+$sy*3])
    }
    my $this_line_cost = 0;
    for 0..8 -> $ly {
        next if $ly >= $sy * 3 && $ly < ($sy+1)*3;
        $this_line_cost += cell-cost($sudoku[$x][$ly])
    }
    my $this_column_cost = 0;
    for 0..8 -> $lx {
        next if $lx >= $sx * 3 && $lx < ($sx+1)*3;
        $this_line_cost += cell-cost($sudoku[$lx][$y])
    }
    return $this_cell_cost*1000 + $this_section_cost + $this_line_cost + $this_column_cost;
}

# Function to decide which possible value to try first
multi likelyhood-value-for-cell($val, Int $cell) {
    return $val == $cell ?? 1 !! 0;
}
multi likelyhood-value-for-cell($val, Array $cell) {
    return $cell.grep({ $val == $_ }) ?? 1 !! 0;
}
sub likelyhood-value-for-cell-wrapper($sudoku, Int $val, Int $x, Int $y) {
    # we give higher points for how many times a value shows up as one
    # of the options in the section, line or column.
    my $this_section = 0;
    my $sx = Int($x / 3);
    my $sy = Int($y / 3);
    for 0..2 X 0..2 -> $lx, $ly {
        $this_section += likelyhood-value-for-cell($val, $sudoku[$lx+$sx*3][$ly+$sy*3])
    }
    my $this_line = 0;
    for 0..8 -> $ly {
        next if $ly >= $sy * 3 && $ly < ($sy+1)*3;
        $this_line += likelyhood-value-for-cell($val, $sudoku[$x][$ly])
    }
    my $this_column = 0;
    for 0..8 -> $lx {
        next if $lx >= $sx * 3 && $lx < ($sx+1)*3;
        $this_line += likelyhood-value-for-cell($val, $sudoku[$lx][$y])
    }
    return $this_section + $this_line + $this_column;
}

sub find-implicit-answers($sudoku, Int $level) {
    my Bool $resolved = False;
    for 0..8 X 0..8 -> $x, $y {
        next unless $sudoku[$x][$y] ~~ Array;
        for @($sudoku[$x][$y]) -> $val {
            # If this is the only cell with this val as a possibility,
            # just make it resolved already
            my $matching = likelyhood-value-for-cell-wrapper($sudoku, $val, $x, $y);
            if ($matching == 1) {
                $sudoku[$x][$y] = $val;
                #say '.' x $level ~ ($x+1)~" "~($y+1)~" solved implicitly...";
                $resolved = True;
            }
        }
    }
    return $resolved;
}

my @cells;
for 0..8 X 0..8 -> $x, $y {
    push @cells, [ $x, $y ];
}

sub solve-sudoku($sudoku, Int $level = 1) {
    # Tentative optimization...
    # cleanup the impossible values first,
    if (cleanup-impossible-values($sudoku, $level)) {
        # try to find implicit answers
        while (find-implicit-answers($sudoku, $level)) {
            # and every time you find some, re-do the cleanup and try again
            cleanup-impossible-values($sudoku, $level);
        }
        # start with the cells closer to a solution, to reduce the
        # amount of guessing
        for sort { cell-cost-wrapper($sudoku, $_) }, @cells {
            my ($x, $y) = @($_);
            next unless $sudoku[$x][$y] ~~ Array;
            # Now sort the options according to how likely it is for
            # it to be the actual answer to this cell
            for sort { likelyhood-value-for-cell-wrapper($sudoku, $_, $x, $y) }, @($sudoku[$x][$y]) {
                say '.' x $level ~ "Trying $_ on "~($x+1)~","~($y+1);
                my $solution = try-value($sudoku, $x, $y, $_, $level+1);
                if ($solution) { 
                    say '.' x $level ~ "Solved... ($_ on "~($x+1)~" "~($y+1)~")";
                    return $solution;
                }
            }
            say '.' x $level ~ "Backtrack, path unsolvable... (on "~($x+1)~" "~($y+1)~")";
            return 0;
        }
        return $sudoku;
    } else {
        return 0;
    }    
}

my $easy_sudoku =
    map { [ map { $_ == 0 ?? [1..9] !! $_+0  }, @($_) ] },
    [ 0,0,8,0,3,0,5,4,0 ],
    [ 3,0,0,4,0,7,9,0,0 ],
    [ 4,1,0,0,0,8,0,0,2 ],
    [ 0,4,3,5,0,2,0,6,0 ],
    [ 5,0,0,0,0,0,0,0,8 ],
    [ 0,6,0,3,0,9,4,1,0 ],
    [ 1,0,0,8,0,0,0,2,7 ],
    [ 0,0,5,6,0,3,0,0,4 ],
    [ 0,2,9,0,7,0,8,0,0 ];

my $medium_sudoku =
    map { [ map { $_ == 0 ?? [1..9] !! $_+0  }, @($_) ] },
    [ 0,0,6,2,4,0,0,3,0 ],
    [ 0,3,0,0,0,0,0,9,0 ],
    [ 2,0,0,0,0,0,0,7,0 ],
    [ 5,0,0,8,0,0,0,2,0 ],
    [ 0,0,1,0,0,0,6,0,0 ],
    [ 0,2,0,0,0,3,0,0,7 ],
    [ 0,5,0,0,0,0,0,0,3 ],
    [ 0,9,0,0,0,0,0,8,0 ],
    [ 0,1,0,0,6,2,5,0,0 ];

my $medium_sudoku2 =
    map { [ map { $_ == 0 ?? [1..9] !! $_+0  }, @($_) ] },
    [ 8,1,0,0,0,0,0,6,5 ],
    [ 0,0,3,1,0,9,7,0,0 ],
    [ 0,0,0,0,6,0,0,0,0 ],
    [ 3,0,0,0,1,0,0,0,9 ],
    [ 0,0,0,8,3,7,0,0,0 ],
    [ 1,0,0,0,5,0,0,0,7 ],
    [ 0,0,0,0,2,0,0,0,0 ],
    [ 0,0,7,4,0,8,3,0,0 ],
    [ 4,5,0,0,0,0,0,9,6 ];

my $hard_sudoku =
    map { [ map { $_ == 0 ?? [1..9] !! $_+0  }, @($_) ] },
    [ 8,5,0,0,0,2,4,0,0 ],
    [ 7,2,0,0,0,0,0,0,9 ],
    [ 0,0,4,0,0,0,0,0,0 ],
    [ 0,0,0,1,0,7,0,0,2 ],
    [ 3,0,5,0,0,0,9,0,0 ],
    [ 0,4,0,0,0,0,0,0,0 ],
    [ 0,0,0,0,8,0,0,7,0 ],
    [ 0,1,7,0,0,0,0,0,0 ],
    [ 0,0,0,0,3,6,0,4,0 ];

my $hard_sudoku2 =
    map { [ map { $_ == 0 ?? [1..9] !! $_+0  }, @($_) ] },
    [ 0,0,0,0,3,7,6,0,0 ],
    [ 0,0,0,6,0,0,0,9,0 ],
    [ 0,0,8,0,0,0,0,0,4 ],
    [ 0,9,0,0,0,0,0,0,1 ],
    [ 6,0,0,0,0,0,0,0,9 ],
    [ 3,0,0,0,0,0,0,4,0 ],
    [ 7,0,0,0,0,0,8,0,0 ],
    [ 0,1,0,0,0,9,0,0,0 ],
    [ 0,0,2,5,4,0,0,0,0 ];

my $solved = solve-sudoku($hard_sudoku);
if $solved {
    print-sudoku($solved,0);
} else {
    say "unsolvable.";
}

# Utility function, not really part of the solution
sub clone-sudoku($sudoku) {
    my $clone;
    for 0..8 X 0..8 -> $x, $y {
        $clone[$x][$y] = $sudoku[$x][$y];
    }
    return $clone;
}

# Utility function, not really part of the solution
sub print-sudoku($sudoku, Int $level = 1) {
    say '.' x $level ~ '-' x 5*9;
    say '.' x $level ~ (map -> $row {
        (map -> $cell {
            $cell ~~ Array ?? "#{$cell.elems}#" !! " $cell " 
         }, @($row)).join("  ") 
                        }, @($sudoku)).join("\n"~('.'x$level));
}

