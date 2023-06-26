DBF 
----

Raku module that reads dBASE III files (version 3) and returns the data as native Raku data types for further processing.

This started as a collection of code snippets from the article [dBASE: Parsing a Binary File Format With Raku](https://dev.to/uzluisf/dbase-parsing-a-binary-file-format-with-raku-2fm6), which I ultimately turned into a small module. 

SYNOPSIS
--------

```raku
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
```

INSTALLATION
------------

You'll need a package manager. I'm using `zef` here:

```terminal
$ cd raku-dbf-reader-art
$ zef install .
```

RUNNING
-------

If you don't want to install `DBF`, you can run `bin/dbf.raku` as follows:

```terminal
$ cd raku-dbf-reader-art
$ RAKULIB=./lib raku bin/dbf.raku -f=data/world.dbf
```

Otherwise:

```terminal
$ raku bin/dbf.raku -f=data/world.dbf
```

