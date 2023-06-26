class DBF::FileHeader {
    has IO::Handle:D $.fh is required('cannot read data without file handle');

    has Str  $.version              is built(False);
    has Str  $.last-updated         is built(False);
    has UInt $.record-count         is built(False);
    has UInt $.header-length        is built(False);
    has UInt $.record-length        is built(False);
    has Bool $.transaction-complete is built(False);
    has Bool $.db-encrypted         is built(False);
    has Bool $.prod-mdx             is built(False);
    has UInt $.lang-driver          is built(False);

    method TWEAK {
        my $data = $!fh.read: 32;
        self!read-metadata($data);
    }

    method !read-metadata($data) {
        my $version = $data[0];

        unless $version == 0x03 {
            die "Only dBase III without memo file supported";
        }
        $!version = 'dBase III without memo file';

        my $year  = $data[1];
	    my $month = $data[2];
	    my $day   = $data[3];
	    $!last-updated = Date.new(
            :year($year + 1900),
            :$month,
            :$day,
            :formatter({ "%04d-%02d-%02d".sprintf(.year, .month, .day) })
        ).Str;

	    $!record-count         = $data.read-uint32(4, LittleEndian);
	    $!header-length        = $data.read-uint16(8, LittleEndian);
	    $!record-length        = $data.read-uint16(10, LittleEndian);
	    $!transaction-complete = $data[14] != 1;
	    $!db-encrypted         = $data[15] == 1;
	    $!prod-mdx             = $data[28] == 1;
	    $!lang-driver          = $data[29];
    }
}

class DBF::Field {
    has Str $.name            is required('field must have a name');
    has Str $.type            is required('field must have a type');
    has Int $.length          is required('field must have a length');
    has Int $.decimal-places;
}

class DBF::FieldDescriptorArray {
    has $.fh            is required('cannot read data without file handle');
    has $.header-length is required('cannot read records without knowing where to start');

    has @.fields is built(False);

    method TWEAK {
        self!read-fields;
    }

    method !read-fields {
	    constant $FIELD-TERMINATOR = 0x0D;
        constant $FIELD-TERMINATOR-LENGTH = 1;
	    constant $METADATA-LENGTH = 32;
	    constant $FIELD-LENGTH = 32;
	    
	    my $TOTAL-FIELD-BYTES = $!header-length - $METADATA-LENGTH - $FIELD-TERMINATOR-LENGTH;
	    my $FIELDS-COUNT = $TOTAL-FIELD-BYTES / $FIELD-LENGTH;
	    my $buffer = $!fh.read($TOTAL-FIELD-BYTES);
	    
	    my $field-terminator = $!fh.read(1);
	    unless $field-terminator[0] == $FIELD-TERMINATOR {
	        die 'Wrong number of bytes for fields'
	    }
	    
	    loop (my $i = 0; $i < $FIELDS-COUNT; $i++) {
	        my $field = $buffer.subbuf($FIELD-LENGTH * $i, $FIELD-LENGTH);
	        my $name = $field.subbuf(0, 10).decode('ascii').subst(/\x[00]+/, '');
	        my $type = $field.subbuf(11, 1).decode('ascii');
	        my $length = $field[16];
	        my $decimal-places = $field[17];
	        @!fields.push: DBF::Field.new(:$name, :$type, :$length, :$decimal-places);
	    }
    }
}

class DBF::RecordsDB {
    has IO::Handle:D                $.fh            is required('cannot read data without file handle');
    has UInt:D                      $.record-count  is required('must know number of records');
    has UInt:D                      $.record-length is required("must know each record's length");
    has DBF::FieldDescriptorArray:D $.fields        is required('must have fields');

    has @.records is built(False);

    submethod TWEAK {
        self!read-records;
    }

    method !read-records {
        constant $DELETION-FLAG = 0x2A;
        constant $HEADER-LENGTH = 32;
        loop (my $i = 0; $i < $!record-count; $i++) {
            my %record;

            my $buffer = $!fh.read($!record-length);
            %record{'deleted'} = $buffer[0] == $DELETION-FLAG;

            my $record-offset = 1;
            for $!fields.fields -> $field {
                my $buf = $buffer.subbuf($record-offset, $field.length);
                my $value = do given $field.type {
                    when 'C' { $buf.decode('utf8-c8').trim }
                    when 'N' { $buf.decode('ascii').Num }
                    when 'L' {
                        my $flag = $buf.decode('ascii').trim;
                        'YyTt'.contains($flag) ?? True !! 'NnFf'.contains($flag) ?? False !! Bool;
                    }
                    when 'D' {
                        my $date = $buf.decode('ascii');
                        my ($year, $month, $day) = .substr(0, 4), .substr(4, 2), .substr(6, 2) given $date;
                        Date.new: :$year, :$month, :$day;
                    }
                    when 'F' { $buf.decode('ascii').Num }
                }
                %record{$field.name} = $value;
                $record-offset += $field.length;
            }
            @!records.push: %record;
        }
    }
}

class DBF {
    has Str:D $.filepath is required('must read dBASE contents from file');

    has FileHeader           $!h;
    has FieldDescriptorArray $!f;
    has RecordsDB            $!r;

    submethod TWEAK {
	    my $fh = $!filepath.IO.open: :r, :bin;
	    
	    $!h = FileHeader.new: :$fh;
	    my $header-length = $!h.header-length;

	    $!f = FieldDescriptorArray.new: :$fh, :$header-length;

        my $record-count = $!h.record-count;
        my $record-length = $!h.record-length;
        $!r = RecordsDB.new: :$fh, :$record-count, :$record-length, :fields($!f);

        $fh.close;
    }

    method header {
        %(
            version => $!h.version, 
            last-updated => $!h.last-updated,
            record-count => $!h.record-count,
            header-length => $!h.header-length,
            record-length => $!h.record-length,
            transaction-complete => $!h.transaction-complete,
            db-encrypted => $!h.db-encrypted,
            prod-mdx => $!h.prod-mdx,
            lang-driver => $!h.lang-driver,
        );
    }

    method fields {
        $!f.fields;
    }

    method records {
        $!r.records;
    }
}

=begin pod

=head2 DBF 

Raku module that reads dBASE III files (version 3) and returns the
data as native Raku data types for further processing.

This started as a collection of code snippets from the article L<dBASE: Parsing
a Binary File Format With Raku|https://dev.to/uzluisf/dbase-parsing-a-binary-file-format-with-raku-2fm6>,
which I ultimately turned into a small module. 

=head2 SYNOPSIS

=begin code :lang<raku>
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
=end code

=head2 INSTALLATION

You'll need a package manager. I'm using C<zef> here:

=begin code :lang<terminal>
$ cd raku-dbf-reader-art
$ zef install .
=end code

=head2 RUNNING

If you don't want to install C<DBF>, you can run C<bin/dbf.raku> as follows:

=begin code :lang<terminal>
$ cd raku-dbf-reader-art
$ RAKULIB=./lib raku bin/dbf.raku -f=data/world.dbf
=end code

Otherwise:

=begin code :lang<terminal>
$ raku bin/dbf.raku -f=data/world.dbf
=end code

=end pod
