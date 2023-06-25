use DBF;

#| Print to STDOUT the DBF file's contents as a CSV file.
multi MAIN(
    Str:D :f(:$filepath) where *.IO.f #= Filepath to DBF database file.
) {
    given DBF.new: :$filepath {
        my @columns = .fields».name;
        $*OUT.spurt: @columns.join(',') ~ "\n";
        
        for .records -> %record {
            my $row = @columns.map({
                my $value = %record{$^field}.Str;
                $value.contains(',') ?? qq`"$value"` !! $value;
            }).join(',');
            $*OUT.spurt: $row ~ "\n";
        }
    }
}
