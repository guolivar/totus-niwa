#!/usr/bin/env perl
#

=head1 NAME

loadCensus.pl - loads Census Meshblock (MB) dataset to TOTUS's census schema

=head1 SYNOPSIS

loadCensus.pl -i <data> -s <database server> -d <database name> -u <database user> -p <database password> -h

=head1 ARGUMENTS

  --help          Brief help message

  --input         Census data directory holding Excel files

  --server        Name of postgres server hosting TOTUS database

  --database      Name of TOTUS database

  --user          TOTUS schema admin user

  --password      Password for above user

  --config        The INI configuration file that maps the spread sheets to topics

  --trace         Enable tracing statements

=cut

use strict;
use warnings;
use DBI;
use DBI::Const::GetInfoType;
use Getopt::Long;
use Pod::Usage;
use Carp;
use Data::Dumper;
use Log::Log4perl;
use Log::Log4perl::Level;
use Spreadsheet::ParseExcel;

=pod

=head1 FUNCTIONS

=over 

=item C<logger_init()>

Initialises logger and sets up correctly formatted log output

=cut

# setup logger
sub logger_init {
  Log::Log4perl->init(\q/
    log4perl.rootLogger=DEBUG, SCREEN
    log4perl.appender.SCREEN=Log::Log4perl::Appender::Screen
    log4perl.appender.SCREEN.Threshold = TRACE
    log4perl.appender.SCREEN.layout=PatternLayout
    log4perl.appender.SCREEN.layout.cspec.N = sub { \
      my ($layout, $message, $category, $priority, $caller_level) = @_ ; \
      my %cvt = ( \
         'FATAL' => 'FATAL', \
         'ERROR' => 'ERROR', \
         'WARN'  => 'WARNING', \
         'INFO'  => 'INFO', \
         'DEBUG' => 'DEBUG', \
         'TRACE' => 'TRACE' \
      ); \
      return $cvt{$priority}; \
    }
    log4perl.appender.SCREEN.layout.ConversionPattern=[%d] %-7N : %m%n/
  );
  return Log::Log4perl->get_logger()
}

my $logger = logger_init ();

=pod

=item C<FATAL ($message)>

Logs fatal errors, these are unrecoverable errors and will result in the process halting

=item C<ERROR ($message)>

Logs important, but recoverable errors

=item C<WARN ($message)>

Logs warnings, these are not errors, but could possible lead to problems

=item C<DEBUG ($message)>

Logs pure debug statements, these can safely be ignored

=item C<INFO ($message)>

Logs program output and normal information about actions taken

=item C<TRACE ($message)>

Trace output when enabled, useful for debugging

=cut

sub FATAL ($) { $logger->fatal(@_); die "Signalled fatal error"; }
sub ERROR ($) { $logger->error(@_); }
sub WARN ($)  { $logger->warn(@_); }
sub DEBUG ($) { $logger->debug(@_); }
sub INFO ($)  { $logger->info(@_); }
sub TRACE($)  { $logger->trace(@_); }

=pod

=item C<parseConfig ($configfile)>

Parses a INI style configuration file and returns it as an associative array of INI sections,
each sections has its parameters and values stored as key/value pairs

=over

=item $configfile

The name of INI configuration file to parse. The INI file must have the following structure:

 [TOPIC]
 code           = topic code descriptor
 description    = topic description
 spreadsheets   = comma separated list of input spreadsheets to parse for this topic
 adminsheet     = the sheet number for the admin data
 meshblocksheet = the sheet number for the meshblock data

I<code> and I<description> is used to populate the I<topic> table fields in the database. The rest is used for parsing
the data.

The topic configuration can be accessed by headings, eg. $config->{TOPIC}

=back

=cut

sub parseConfig ($) {
  my $configfile = shift;
  my $config = {};
  my $section;
  my $params = {};
  my $multiline = 0;
  my ($key, $value);

  open FH, $configfile or die "Unable to open configuration file: $configfile";

  while (<FH>) {
    # ignore comments and empty lines
    if (!m/^\s*$/ && !m /^\s*#/) {
      if (m/^\[\D+\]$/) {
        if ($section) {
          # store away previous section
          $config->{$section} = $params;
          $section = undef;
          $params  = undef;
        }
        $section = $_;
        chomp ($section);
        $section =~ s/^\[//;
        $section =~ s/\]$//;
      }
      else {
        if ($section) {
          if ($multiline) {
            # inside, section, inside multiline params
            $value = $_;
            if (m/^"$/) {
              # end of multiline params
              $value =~ s/"$//;
              $multiline = 0;
            }
            # append to param
            $params->{$key} .= $value;
          }
          else {
            # inside section, parse params
            ($key, $value) = split (/=/);

            $key   =~ s/\s+$//g;
            $value =~ s/^\s+//g;

            if ($value =~ m/^"\D+"/) {
              $value =~ s/"//g;
              chomp ($value);
            }
            elsif ($value =~ m/^"/) {
              $value =~ s/^"//;
              $multiline = 1;
            }
            else {
              chomp ($value);
            }
            $params->{$key} = $value;
          }
        }
      }
    }
  }

  if ($section) {
    # store away last section
    $config->{$section} = $params;
    $section = undef;
  }

  close FH;

  return $config;
}

=pod

=back

=cut

# to prevent memory bloat by caching the whole spreadsheet we need to use a custom
# cell handler for ParseExcel, we need to keep track of row and column within the
# cell handler, so it's all encapsulated in a class
use lib sub {

=pod

=head1 NAME

AdminHierarchy

=head1 DESCRIPTION

=over

=item parse Excel, pass in cell handler to parse and cache admin area sheet only, the rest is ignored

=item populate database with admin areas (only if not present)

=item map the census keys to the database keys

=back

=head1 METHODS

=over

=cut

  package AdminHierarchy;

  use Data::Dumper;

  our $AUTOLOAD;

=pod

=item C<new ($class, $dbh)>

Instantiate new class with given database handle

=cut

  sub new ($) {
    my $class = shift;

    my $self = {
      _dbh        => shift, # initialised with database handle
      _parser     => undef, # the admin sheet parser
      _sheetidx   => undef, # index of sheet to parse for admin data
      _hierarchy  => undef, # initialised with definition of hierarchy, amended as we parse
      _index      => undef, # index on hierarchy by column
      _data       => undef, # filled in as we parse
      _record     => undef, # row record
      _lastcol    => undef, # number of last column in sheet
      _lastrow    => undef, # number of last row in sheet
      _rootcol    => undef, # root column in spreadsheet
      _admintypes => undef, # map's the admin type code to database ids
      _meshblocks => undef  # map census ids to database ids
    };

    bless $self, $class;

    # init parser and hierarchy after being blessed
    $self->initParser();
    $self->initAdminHierarchy();

    # init admin data tree
    $self->{_data} = {};

    return $self;
  }

=pod

=item C<initParser ()>

Initialise the admin hierarchy sheet parser

=cut

  sub initParser ($) {
    my $self = shift;

    # we pass in custom cell handlers for each sheet, therefore we need to
    # instantiate new parsers each time we read a sheet from a spreadsheet
    my $callback = sub { $self->adminSheetHandler (@_) };

    $self->{_parser} = Spreadsheet::ParseExcel->new (
      CellHandler => \&$callback,
      NotSetCell  => 1
    );
  }

=pod

=item C<initAdminHierarchy ()>

Initialiase the internal admin hierarchy definition which is amended when parsing the
sheet header row.

=cut

  # defines the admin hierarchy
  sub initAdminHierarchy ($) {
    my $self = shift;

    # stranded hierarchy nodes
    $self->{_hierarchy} = {
      'Regional Council' => {
        'code' => 'RC',
        'desc' => 'Regional Council'
      },
      'Territorial Authority' => {
        'code' => 'TA',
        'desc' => 'Territorial Authority'
      },
      'Ward' => {
        'code' => 'WA',
        'desc' => 'Ward'
      },
      'Area Unit' => {
        'code' => 'AU',
        'desc' => 'Area Unit'
      },
      'Meshblock' => {
        'code' => 'MB',
        'desc' => 'Meshblock'
      }
    };

    # root has no parent, leaf has no child, rest inner nodes
    $self->linkAdminHierarchy ('Regional Council', undef, 'Territorial Authority');
    $self->linkAdminHierarchy ('Territorial Authority', 'Regional Council', 'Ward');
    $self->linkAdminHierarchy ('Ward', 'Territorial Authority', 'Area Unit');
    $self->linkAdminHierarchy ('Area Unit', 'Ward', 'Meshblock');
    $self->linkAdminHierarchy ('Meshblock', 'Area Unit', undef);
  }

=pod

=item C<linkAdminHierarchy ()>

=cut

  sub linkAdminHierarchy ($$$$) {
    my ($self, $nodeKey, $parentKey, $childKey) = @_;

    # $self is the implicit argument eg. this pointer
    if ($parentKey && exists $self->{_hierarchy}->{$parentKey}) {
      $self->{_hierarchy}->{$nodeKey}->{parent} = $self->{_hierarchy}->{$parentKey};
    }
    if ($childKey && exists $self->{_hierarchy}->{$childKey}) {
      $self->{_hierarchy}->{$nodeKey}->{child}  = $self->{_hierarchy}->{$childKey};
    }
  }

# structure of a cell as parsed
#
#         bless( {
#                  'Code' => undef,
#                  'Type' => 'Text',
#                  'Val' => 'Meshblock (2006 Areas)',
#                  '_Value' => 'Meshblock (2006 Areas)',
#                  'FormatNo' => 83,
#                  '_Kind' => 'PackedIdx',
#                  'Format' => bless( {
#                                       'BdrDiag' => [
#                                                      0,
#                                                      0,
#                                                      0
#                                                    ],
#                                       'Fill' => [
#                                                   0,
#                                                   64,
#                                                   65
#                                                 ],
#                                       'Shrink' => 0,
#                                       'Font' => bless( {
#                                                          'Underline' => 0,
#                                                          'Strikeout' => 0,
#                                                          'Bold' => 1,
#                                                          'Height' => '8',
#                                                          'Italic' => 0,
#                                                          'Name' => 'Arial',
#                                                          'UnderlineStyle' => 0,
#                                                          'Super' => 0,
#                                                          'Attr' => 1,
#                                                          'Color' => 32767
#                                                        }, 'Spreadsheet::ParseExcel::Font' ),
#                                       'FontNo' => 10,
#                                       'Wrap' => 1,
#                                       'AlignV' => '1',
#                                       'JustLast' => 0,
#                                       'AlignH' => 2,
#                                       'ReadDir' => 0,
#                                       'Style' => 0,
#                                       'Indent' => 0,
#                                       'Merge' => 0,
#                                       'BdrStyle' => [
#                                                       0,
#                                                       1,
#                                                       0,
#                                                       0
#                                                     ],
#                                       'Lock' => 1,
#                                       'Key123' => 0,
#                                       'BdrColor' => [
#                                                       0,
#                                                       64,
#                                                       0,
#                                                       0
#                                                     ],
#                                       'Hidden' => 0,
#                                       'FmtIdx' => 0,
#                                       'Rotate' => 0
#                                     }, 'Spreadsheet::ParseExcel::Format' )
#                }, 'Spreadsheet::ParseExcel::Cell' );
# 

=pod 

=item C<adminSheetHandler ($workbook, $sheetIndex, $row, $column, $cell)>

=cut

  sub adminSheetHandler () {
    my ($self, $workbook, $sheetIndex, $row, $column, $cell) = @_;

    # check that we're parsing the sheet specified in configuration
    if (!$row && !$column) {
      my $abort = 0;

      if ($sheetIndex == $self->{_sheetidx}) {
        # check that is has an admin sheet (ends with Key)
        if (!(($workbook->worksheets())[$sheetIndex]->{Name} =~ m/\s+-\s+Key$/)) {
          main::ERROR ("Skipping invalid admin sheet: " . ($workbook->worksheets())[$sheetIndex]->{Name});
          $abort = 1;
        }
        else {
          main::INFO ("Processing admin sheet: " . ($workbook->worksheets())[$sheetIndex]->{Name});
        }
      }
      elsif ($sheetIndex > $self->{_sheetidx}) {
        # we've over run it, abort
        $abort = 1;
      }
      if ($abort) {
        $workbook->ParseAbort(1);
        return;
      }
    }

    if ($sheetIndex != $self->{_sheetidx}) {
      # skip each cell in this sheet, not the sheet we're after
      return;
    }

    # parse header
    # the hierarchy fields are amended only once for the first header row
    if (!$row) {
      # reference to hierarchy definition
      my $hierarchy = $self->{_hierarchy};
      my $index     = $self->{_index};

      # check if it's a code or description field
      my $headerField = $cell->{Val};
      
      # strip of year annotation
      my $field = $headerField;
      $field    =~ s/\s{1}\([0-9]{4} Areas\)$//;
      
      # capture type, default to code
      $field =~ m/\b\s{1}(\S+)$/;
      my $type = $1 || 'Code';

      # strip of type and trailing white space
      $field =~ s/$type//;
      $field =~ s/\s+$//;

      # store the column index for id and description fields
      if ($type =~ /code/i) {
        $hierarchy->{$field}->{idfield} = $column;
      }
      elsif ($type =~ /description/i) {
        $hierarchy->{$field}->{descfield} = $column;
      }
      else {
        main::FATAL ("Unknown admin header field type found: $type for field: $headerField");
      }

      # construct index on hierachy definition to assist parsing, don't work of the 
      # copy of object reference $index - not instantiated yet
      $self->{_index}->{$column} = $hierarchy->{$field};

      if (!$column) {
        my $worksheet = ($workbook->worksheets())[$sheetIndex];

        $self->{_lastcol} = ($worksheet->col_range())[1];

        main::TRACE ("Number of columns: " . ($self->{_lastcol} + 1));
      }

      if ($column == $self->{_lastcol}) {
        # find the root index when we have a complete index built up
        foreach my $key (keys %{$hierarchy}) {
          my $admin = $hierarchy->{$key};

          if (!$admin->{parent}) {
            # root has no parent
            $self->{_rootcol} = $admin->{idfield};
            last;
          }
        }

        main::TRACE ("Root of hierarchy found at column: $self->{_rootcol}");
      }
    }
    elsif ($row == 1) {
      # nothing to do row 0 and 1 are merged
      if (!$column) {
        main::TRACE ("Admin hierarchy header: " . Dumper ($self->hierarchy()));
        main::TRACE ("Admin hierarchy index: " . Dumper ($self->index()));
        main::TRACE ("Number of columns in sheet : " . $self->lastcol());
      }
    }
    else {
      # build of row record
      $self->{_record}->{$column} = $cell->{Val};

      # parse the record when at last column in row
      if ($column == $self->{_lastcol}) {
        # check if it was an empty row and set last row
        my $checkEmpty = 0;
        foreach my $val (values %{$self->{_record}}) {
          if ($val eq '') {
            $checkEmpty++;
          }
          else {
            # no need to check anymore, got a value, it's a valid row
            last;
          }
        }

        if ($checkEmpty == $self->{_lastcol} + 1) {
          # all columns are empty, set last row
          $self->{_lastrow} = $row;

          main::TRACE ("First empty record = " . Dumper ($self->{_record}) . " found at $row");
        }
        else {
          # parse data using the parsed definition and record when at end of row
          # start at root of admin hierarchy
          my $i       = $self->{_rootcol};
          my $index   = $self->{_index};
          my $parent  = $self->{_data};

          # construct admin data tree until the leaf node is encountered
          # columns index starts at 0, test for undef AKA null
          while (defined $i) {
            my $def  = $index->{$i};
            my $rec  = $self->{_record};
            my $id   = $rec->{$def->{idfield}};
            my $desc = $rec->{$def->{descfield} || $def->{idfield}}; # fall back to id field for description
            my $code = $def->{code};

            if (!$def->{parent}) {
              if (!exists $parent->{$id}) {
                # init top admin areas
                # $parent is the top level of admin area structure
                $parent->{$id} = {
                  description => $desc,
                  children    => { },
                  type        => $code
                };
              }
              # next parent admin area
              $parent = $parent->{$id} ;
            }

            if ($def->{parent}) {
              # attach to parent
              if (!exists $parent->{children}->{$id}) {
                $parent->{children}->{$id} = {
                  description => $desc,
                  children    => { },
                  type        => $code
                };
              }
              # next parent admin area
              $parent = $parent->{children}->{$id};
            }

            # next child column index
            $i = $def->{child}->{idfield};
          }
        }

        # reset record decoupling reference to current record, allow it to be reclaimed
        $self->{_record} = {};
      }
    }

    if ($self->{_lastrow} && $row >= $self->{_lastrow}) {
      # quit at end of sheet, no need to keep parsing
      $workbook->ParseAbort(1);
      return;
    }
  }

=pod

=item C<parse($file, $sheet)>

  Parses the admin hierarchy for a census spreadsheet

=cut

  sub parse ($$$) {
    my ($self, $file, $sheetIndex) = @_;

    # set the sheet index to parse
    $self->{_sheetidx} = $sheetIndex;

    main::INFO ("Parsing Census Admin sheet: $sheetIndex of Excel file: $file");

    # get the parser
    my $parser = $self->{_parser};

    $parser->parse ($file) or main::FATAL ($parser->error());
  }

=pod

=item C<persist()>

Persist admin hierarchy to database

=cut

  sub persist () {
    my $self = shift;

    main::INFO ("Writing Administrative Hierarchy to database");

    my $dbh = $self->{_dbh};
    my $sth;

    eval {
      # set search path for schema
      $dbh->do ("SET search_path = census, public");

      # get last admin serial used
      my $adminTypeId = ($dbh->selectrow_array ("SELECT NEXTVAL ('census.admin_type_id_seq')"))[0];

      # use header to populate the administrative area types
      $sth = $dbh->prepare ("INSERT INTO admin_type (id, code, description) VALUES (?, ?, ?)");

      my $i     = $self->{_rootcol};
      my $index = $self->{_index};

      while (defined $i) {
        my $def = $index->{$i};

        $sth->execute ($adminTypeId, $def->{code}, $def->{desc});

        # store admin types inserted
        $self->{_admintypes}->{$def->{code}} = $adminTypeId;

        # next child column index
        $i = $def->{child}->{idfield};

        # next id
        $adminTypeId++;
      }

      main::TRACE ($self->{_admintypes});

      $sth->finish();

      # fix up admin type id serial
      $dbh->do ("SELECT pg_catalog.SETVAL ('census.admin_type_id_seq', $adminTypeId, false)");

      # get last admin area serial used
      my $adminAreaId = ($dbh->selectrow_array ("SELECT NEXTVAL ('census.admin_area_id_seq')"))[0];

      $sth = $dbh->prepare ("INSERT INTO admin_area (id, parent_id, admin_type_id, census_identifier, description)" .
                            "VALUES (?, ?, ?, ?, ?)");
      
      my $adminAreas = $self->{_data};

      # may have a forest of admin areas, eg. different city councils
      foreach my $adminKey (keys %{$adminAreas}) {
        my $adminArea = $adminAreas->{$adminKey};

        # roots are their own parents
        my $parentId  = $adminAreaId;

        # process roots, pass in reference to admin area serial
        $self->populateAdminArea ($sth, $adminKey, $adminArea, \$adminAreaId, $parentId);
      }

      $sth->finish();

      # fix up admin area id serial
      $dbh->do ("SELECT pg_catalog.SETVAL ('census.admin_area_id_seq', $adminAreaId, false)");
    };
    if ($@) {
      # cleanup statement handle upon failure
      $sth->finish() if $sth;

      # catch error
      main::FATAL ($@);
    }
  }

=pod

=item C<populateAdminArea ($sth, $areaKey, $adminArea, $adminAreaId, $parentId)>

Helper function to recursively populate admin areas from the root down

=over

=item I<$sth>

Prepared statement handle for populating admin area

=item I<$areaKey>

The census key identifier for the admin area

=item I<$adminArea>

The admin area node to process

=item I<$adminAreaId>

Reference to admin area id serial sequence, will be advanced by this function

=item I<$parentId>

The parent of this admin area node

=back

=cut

  sub populateAdminArea ($$$$$) {
    my ($self, $sth, $areaKey, $adminArea, $adminAreaId, $parentId) = @_;

    my $type   = $adminArea->{type};
    my $desc   = $adminArea->{description};
    my $typeId = $self->{_admintypes}->{$type};

    # for meshblocks we strip of MB and retain only id part
    my $areaId;
    
    if ($type eq 'MB') {
      $areaKey =~ m/^MB\s+([0-9]*)\s*$/;
      $areaId  = $1;

      # cache meshblock census to database id map
      $self->{_meshblocks}->{$areaKey} = $$adminAreaId;
    }
    else {
      $areaId = $areaKey;
    }

    main::TRACE ("Populating node: $$adminAreaId parent: $parentId type: $typeId " .
                 "census key: $areaId description: $desc");
    
    $sth->execute ($$adminAreaId, $parentId, $typeId, $areaId, $desc);

    # set current node as parent and advance to next admin area id
    $parentId = $$adminAreaId++;

    foreach my $childKey (keys %{$adminArea->{children}}) {
      my $child  = $adminArea->{children}->{$childKey};

      # follow path to leaf
      $self->populateAdminArea ($sth, $childKey, $child, $adminAreaId, $parentId);
    }

    # base of recursion reached, no more children to process
    return;
  }

  # destructor stub to prevent autoload from intercepting it
  sub DESTROY {}

  # setters and getters for class fields
  sub AUTOLOAD {
    my $self = shift;
    my $type = ref($self) or main::FATAL ("$self is not an object");

    my $name = $AUTOLOAD;
    $name =~ s/.*://;
    $name = "_$name";

    # make sure a getter/setter has been requested for an existing field
    unless ( exists $self->{$name}) {
      main::FATAL ("Can't access '$name' field in class $type");
    }

    if (@_) {
      # setter
      return $self->{$name} = shift;
    } else {
      # getter
      return $self->{$name};
    }
  }  

=pod

=back

=cut

}; # end of AdminHierarchy

# class to encapsulate processing of demographic data
use lib sub {

=pod

=head1 NAME

Demographic

=head1 DESCRIPTION

=over

=item parses the Meshblock demographic dataset from each Census spreadsheet

=item prepares and populate the category and class data structure in memory

=item populates the demographic data using the class information

=back

=head1 METHODS

=over

=cut

  package Demographic;

  use Data::Dumper;

  our $AUTOLOAD;

=pod

=item C<new ($class, $dbh, $meshblocks)>

Instantiate new class with given database handle and meshblock admin dataset

=cut

  sub new ($$$) {
    my $class = shift;

    my $self = {
      _dbh         => shift, # initialised with database handle
      _topic       => shift, # initialised with topic configuration
      _meshblocks  => shift, # map census ids to database ids
      _parser      => undef, # the admin sheet parser
      _sheetidx    => undef, # index of sheet to parse for meshblock demographic data
      _lastcol     => undef, # number of last column in sheet
      _lastrow     => undef, # number of last row in sheet
      _categories  => undef, # normalised category data and year column mapping
      _classes     => undef, # normalised class data
      _categoryidx => undef, # map column index to a unique database category
      _classidx    => undef, # map column index to a unique database class 
      _serials     => undef, # id sequence for topic, category, class and demographic
      _statements  => undef  # set of prepared statement handles per table
    };

    bless $self, $class;

    # init parser and hierarchy after being blessed
    $self->initParser();

    # init serial keys
    $self->initSerialKeys();

    # init statement handles
    $self->initStatementHandles ();

    return $self;
  }

=pod

=item C<initParser ()>

Initialise the meshblock demographic data sheet parser

=cut

  sub initParser ($) {
    my $self = shift;

    # we pass in custom cell handlers for each sheet, therefore we need to
    # instantiate new parsers each time we read a sheet from a spreadsheet
    my $callback = sub { $self->meshblockSheetHandler (@_) };

    $self->{_parser} = Spreadsheet::ParseExcel->new (
      CellHandler => \&$callback,
      NotSetCell  => 1
    );
  }

=pod

=item C<initSerialKeys ()>

Initialise serial keys for topic, category, class and demographic from database

=cut

  sub initSerialKeys ($) {
    my $self = shift;

    my $dbh = $self->{_dbh};

    foreach my $table (qw(topic category class demographic)) {
      $self->{_serials}->{$table} = ($dbh->selectrow_array ("SELECT NEXTVAL ('census.${table}_id_seq')"))[0]
    }
  }

=pod 

=item C<setSerialKeys ()>

Set database serial keys to internal serials

=cut

  sub setSerialKeys ($) {
    my $self = shift;

    my $dbh = $self->{_dbh};

    foreach my $table (keys %{$self->{_serials}}) {
      $dbh->do ("SELECT pg_catalog.SETVAL ('census.${table}_id_seq', $self->{_serials}->{$table}, false)");
    }
  }
 
=pod

=item C<initStatementHandles ()>

Initialise the statement handles

=cut

  sub initStatementHandles ($) {
    my $self = shift;

    my $dbh = $self->{_dbh};

    foreach my $table (qw(topic category class demographic)) {
      my $sth  = $dbh->column_info('', 'census', $table, '');
      my $info = $sth->fetchall_arrayref({});

      $sth->finish();

      if (! scalar @$info) {
        main::ERROR ("Table: $table does not exist in NEMO");
        return undef;
      }
      
      my ($columns, $placeholders) = ("", "");

      for my $i (0 .. $#$info) {
        my $comma      = $i ? ', ' : '';

        $columns      .= $comma . $info->[$i]->{COLUMN_NAME};
        $placeholders .= "$comma?";
      }

      my $query = "INSERT INTO census.$table ($columns) VALUES ($placeholders)";

      eval {
        $self->{_statements}->{$table} = $dbh->prepare ($query) || die "Cannot prepare statement $query: $DBI::errstr";
        $self->{_statements}->{$table}->{RaiseError} = 1;
        $self->{_statements}->{$table}->{ChopBlanks} = 1;
      };
      if ($@) {
        FATAL ($@);
      }
    }
  }

=pod

=item C<destroyStatementHandles ()>

Destroys the insert statement handles

=cut

  sub destroyStatementHandles ($) {
    my $self = shift;

    foreach my $sth (values %{$self->{_statements}}) {
      $sth->finish();
    }
  }

=pod

=item C<populateTopic ()>

Persist single topic from configuration object passed in to demographic

=cut

  sub populateTopic () {
    my $self = shift;

    my $topic = $self->{_topic};

    # multiple spread sheets per topic, check whether or not this topic has
    # been persisted to database, if not persist it
    if (!$topic->{persisted}) {
      my $sth = $self->{_statements}->{topic};
      my $id = $self->{_serials}->{topic}++;

      $sth->execute (
        $id,
        $topic->{code},
        $topic->{description}
      );

      $topic->{persisted} = 1;
    }
  }

=pod

=item C<populateCategories ()>

Persist the normalised category data structure to database

=cut

  sub populateCategories ($) {
    my $self = shift;

    main::INFO ("Populating categories");

    my $sth = $self->{_statements}->{category};

    my $topicId = $self->{_serials}->{topic} - 1;

    foreach my $category (values %{$self->{_categories}}) {
      main::TRACE ("Populating category: " . Dumper ($category));

      eval {
        $sth->execute (
          $category->{id},
          $topicId,
          $category->{code},
          $category->{desc}
        );
      };
      if ($@) {
        main::ERROR ("Failed inserting category [$category->{id}, $topicId, $category->{code}, $category->{desc}]");
        main::FATAL ($@);
      }
    }
  }

=pod

=item C<populateClasses ()>

Persist the normalised category data structure to database

=cut

  sub populateClasses ($) {
    my $self = shift;

    main::INFO ("Populating classes");

    my $sth = $self->{_statements}->{class};

    foreach my $class (values %{$self->{_classes}}) {
      main::TRACE ("Populating class: " . Dumper ($class));

      eval {
        $sth->execute (
          $class->{id},
          $class->{category},
          $class->{code},
          $class->{desc}
        );
      };
      if ($@) {
        main::ERROR ("Failed inserting class [$class->{id}, $class->{category}, $class->{code}, $class->{desc}]");
        main::FATAL ($@);
      }
    }
  }

=pod

=item C<formatCode ($code)>

Helper function, not a class function, to format a code from description field

=cut

  sub formatCode ($) {
    my $desc = shift;
    my $code = "";
    my $done = 0;

    # most category and classes are string descriptions, some are monetary ranges
    # these fail the logic below, instead we create the class name from range
    if (length ($desc) < 32 && ($desc =~ m/\$[0-9]+/ || $desc =~ m/[0-9][0-9] Years/)) {
      # strip out comma, replace spaces with _
      $code = uc($desc);
      $code =~ s/,//g;
      $code =~ s/-/TO/g;
      $code =~ s/\s/_/g;

      $done = 1;
    }

    if (!$done) {
      # first try to split on commas see if we have a phrase that will fit
      foreach my $str (split (/,/, $desc)) {
        # lets split on spaces
        foreach my $word (split / /, $str) {
          # by default we use the first character only
          my $len = 1;

          # if the word is a numeric we take up to the first 4 to cover different ranges
          if ($word =~ m/^[0-9][0-9]+$/) {
            $len = length($word) > 4 ? 4 : length($word);
          }

          # check if current code plus single letter meets requirement
          if (length ($code) + $len < 32) {
            my $c = substr ($word, 0, $len);

            # do not use ( in a code, instead use the next letter
            $c = substr ($word, 1, $len) if $c eq '(';

            # append to code
            $code .= uc($c);
          }
          else {
            $done = 1;
            last;
          }
        }
        last if $done;
      }
    }

    return $code;
  }

=pod

=item C<meshblockSheetHandler ($workbook, $sheetIndex, $row, $column, $cell)>

Meshblock sheet cell parser handler, each cell possible results in a database commit

=cut

  sub meshblockSheetHandler () {
    my ($self, $workbook, $sheetIndex, $row, $column, $cell) = @_;

    # check that we're parsing the meshblock sheet specified in configuration
    if (!$row && !$column) {
      my $abort = 0;

      if ($sheetIndex == $self->{_sheetidx}) {
        # check that is has an meshblock demographic data sheet (ends with MB)
        if (!(($workbook->worksheets())[$sheetIndex]->{Name} =~ m/\s+-\s+MB$/)) {
          main::ERROR ("Skipping invalid meshblock demographic data sheet: " . ($workbook->worksheets())[$sheetIndex]->{Name});
          $abort = 1;
        }
        else {
          main::INFO ("Processing meshblock demographic data sheet: " . ($workbook->worksheets())[$sheetIndex]->{Name});
        }
      }
      elsif ($sheetIndex > $self->{_sheetidx}) {
        # we've over run it, abort
        $abort = 1;
      }
      if ($abort) {
        $workbook->ParseAbort(1);
        return;
      }
    }

    if ($sheetIndex != $self->{_sheetidx}) {
      # skip each cell in this sheet, not the sheet we're after
      return;
    }

    # first row is the category header
    if (!$row) {
      # col_range provide inconsistent results, just set to current column, when at end of row this
      # will be the last column
      $self->{_lastcol} = $column;

      # parse category
      my $category = $cell->{Val};

      # excluse the meshblock ID field, not a valid category
      if ($category !~ m/^Meshblock\s+\([0-9]{4}\s+Areas\)\s*$/) {
        # check if the column in header contains a category
        if ($category) {
          # strip out and capture year from header
          # latest census always holds the previous 2 census data
          $category =~ s/^([0-9]{4})[ Census, | ]//;
          my $year = $1;

          main::TRACE ("Category [$column]: $category year: $year");

          my $id   = $self->{_serials}->{category}++;
          my $code = formatCode ($category)  . ' ' . $id;
          
          if (!exists $self->{_categories}->{$category}) {
            $self->{_categories}->{$category} = {
                                                  id   => $id,
                                                  code => $code,
                                                  desc => $category,
                                                  year => {
                                                    $column => $year
                                                  }
                                                };
          }
          else {
            # add year to column mapping, this is needed when parsing demographic
            # data per class
            $self->{_categories}->{$category}->{year}->{$column} = $year;
          }

          # add column index to refer to category entry
          $self->{_categoryidx}->{$column} = $self->{_categories}->{$category};
        }
        else {
          # empty means same category, link to previous column
          $self->{_categoryidx}->{$column} = $self->{_categoryidx}->{$column - 1};

          $self->{_categoryidx}->{$column}->{year}->{$column} =
            $self->{_categoryidx}->{$column - 1}->{year}->{$column - 1};
        }
      }
    }
    # second row is the class header
    elsif ($row == 1) {
      if (!$column) {
        main::TRACE ("Number of columns: " . ($self->{_lastcol} + 1));

        main::TRACE ("Categories : " . Dumper ($self->{_categories}));
      }

      # last column is set according to the category header, a class cannot
      # exist without one
      if ($column <= $self->{_lastcol}) {
        # skip first column which contains the meshblock id
        if ($column) {
          # parse class
          main::TRACE ("Class [$column] $cell->{Val}");

          # the classes are a sub header, when empty the header and sub-header are a merged cell
          # instead use it's parent category name
          my $class = (! defined $cell->{Val} || $cell->{Val} eq '') 
                      ? $self->{_categoryidx}->{$column}->{desc} 
                      : $cell->{Val};

          # multiple census datasets is present in a meshblock sheet
          # normalise the classes, use the category and class name as key
          my $classKey = $self->{_categoryidx}->{$column}->{desc} . ' ' . $class;

          if (!exists $self->{_classes}->{$classKey}) {
            # advance id sequence
            my $id   = $self->{_serials}->{class}++;
            my $code = formatCode ($class) . ' ' . $id;
          
            # find it's parent category using the column index
            my $categoryId = $self->{_categoryidx}->{$column}->{id};

            # add new class
            $self->{_classes}->{$classKey} = {
                                               id       => $id,
                                               code     => $code,
                                               desc     => $class,
                                               category => $categoryId
                                             };
          };

          $self->{_classidx}->{$column} = $self->{_classes}->{$classKey};

          if ($column == $self->{_lastcol}) {
            main::TRACE ("Classes : " . Dumper ($self->{_classes}));

            # finished parsing classes for this sheet, we're at the end of the row
            # can now safely persist category and classes to the database
            $self->populateTopic();
            $self->populateCategories();
            $self->populateClasses();
          }
        }
      }
    }
    # demographic data rows
    else {
      if (! $column && $row == 2) {
        main::INFO ("Populating meshblock data");
      }

      # construct a complete row record as we parse each cell
      # set ..C as null
      my $val = $cell->{Val} ne '..C' ? $cell->{Val} : undef;

      $self->{_record}->{$column} = $val;

      # the parser's row_range() produces inconsistent results
      # check for an empty record when at last column in row
      if ($column == $self->{_lastcol}) {
        # check if it was an empty row and set last row
        my $checkEmpty = 0;
        foreach my $val (values %{$self->{_record}}) {
          if (!defined $val || $val eq '') {
            $checkEmpty++;
          }
          else {
            # no need to check anymore, got a value, it's a valid row
            last;
          }
        }

        if ($checkEmpty == $self->{_lastcol} + 1) {
          # all columns are empty, set last row
          $self->{_lastrow} = $row;

          main::TRACE ("First empty record = " . Dumper ($self->{_record}) . " found at $row");
        }
        else {
          # safe to populate all cells in record now
          my $rec = $self->{_record};
          my $sth = $self->{_statements}->{demographic};

          # census meshblock id is stored at column index 0
          my $meshblockId = $self->{_meshblocks}->{$rec->{0}};

          for (my $i = 1; $i <= $self->{_lastcol}; $i++) {
            my $id    = $self->{_serials}->{demographic}++;
            my $count = $self->{_record}->{$i};

            # find class id by column index
            my $classId = $self->{_classidx}->{$i}->{id};

            # find category year by column index
            my $year = $self->{_categoryidx}->{$i}->{year}->{$i};

            # only commit meshblock if we have a valid count
            if (defined $count && $count ne '') {
              eval {
                $sth->execute (
                  $id,
                  $meshblockId,
                  $classId,
                  $count,
                  $year
                );
              };
              if ($@) {
                if (!defined $meshblockId) {
                  main::ERROR ("Spreadsheet record: " . Dumper ($rec));
                  main::ERROR ("Missing meshblock $rec->{0} from " . Dumper ($self->{_meshblocks}));
                }

                main::ERROR ("Failed inserting demographic [$row, $i]: $id, $meshblockId, $classId, $count, $year");
                main::FATAL ($@);
              }
            }
          }

          # reset row record
          $self->{_record} = {};
        }
      }
    }

    if ($self->{_lastrow} && $row >= $self->{_lastrow}) {
      # quit at end of sheet, no need to keep parsing
      $workbook->ParseAbort(1);
      return;
    }
  }

=pod

=item C<parse($file, $sheetIndex)>

=cut

  sub parse ($$$) {
    my ($self, $file, $sheetIndex) = @_;

    # set the sheet index to parse
    $self->{_sheetidx} = $sheetIndex;

    main::INFO ("Parsing Census Meshblock sheet: $sheetIndex of Excel file: $file");

    # get the parser
    my $parser = $self->{_parser};

    $parser->parse ($file) or main::FATAL ($parser->error());

    # reset DB keys
    $self->setSerialKeys ();

    # free statement handles
    $self->destroyStatementHandles ();
  }

  # destructor stub to prevent autoload from intercepting it
  sub DESTROY {}

  # setters and getters for class fields
  sub AUTOLOAD {
    my $self = shift;
    my $type = ref($self) or main::FATAL ("$self is not an object");

    my $name = $AUTOLOAD;
    $name =~ s/.*://;
    $name = "_$name";

    # make sure a getter/setter has been requested for an existing field
    unless ( exists $self->{$name}) {
      main::FATAL ("Can't access '$name' field in class $type");
    }

    if (@_) {
      # setter
      return $self->{$name} = shift;
    } else {
      # getter
      return $self->{$name};
    }
  }  

=pod

=back

=cut
};

# main

my %opts = (help => sub { pod2usage(-verbose => 1) });

GetOptions(\%opts,
           "help|?",
           "input=s",
           "server=s",
           "database=s",
           "user=s",
           "password=s",
           "config=s",
           "trace"
          ) or pod2usage(-verbose => 1);

unless ($opts{'input'}) {
  ERROR ("Missing input Census spreadsheet directory");

  die pod2usage (-verbose => 1);
}

unless ($opts{'server'} && $opts{'database'} && $opts{'user'} && $opts{'password'}) {
  ERROR ("Missing database connection parameters");

  die pod2usage (-verbose => 1);
}

unless ($opts{'config'}) {
  ERROR ("Missing Census topic configuration INI file");

  die pod2usage (-verbose => 1);
}

if (exists $opts{'trace'}) {
  $logger->level($TRACE);
}

my $config = parseConfig ($opts{'config'});

INFO ("Connecting to NEMO database: $opts{database}");
my $dbh = DBI->connect (
            "dbi:Pg:dbname=$opts{database};host=$opts{server};port=5432",
            $opts{'user'},
            $opts{'password'},
            {
              PrintWarn   => 1,
              PrintError  => 0,
              RaiseError  => 1,
              HandleError => sub { FATAL(shift) },
              AutoCommit  => 1
            }
          ) || FATAL $DBI::errstr;

# all spreadsheets data is transferred in one big transaction
# a bit of a gamble
$dbh->begin_work();

# Census spreadsheets are all in Latin 1
$dbh->do ('SET client_encoding = latin1') || 
  FATAL ("Unable to set client encoding for census spreadsheets to Latin 1");

eval {
  # all spreadsheets contain admin hierarchy sheet, parse them all
  # and construct normalised hierarchy before persisting in database
  my $adminHierarchy = AdminHierarchy->new($dbh);

  for my $key (sort { $a cmp $b } keys %$config) {
    my $topicConfig = $config->{$key};
    my $adminSheet  = $topicConfig->{adminsheet};

    for my $inputXL (split (/,/, $topicConfig->{'spreadsheets'})) {
      my $inputXLFile = "$opts{input}/$inputXL";

      $adminHierarchy->parse ($inputXLFile, $adminSheet);
    }
  }

  $adminHierarchy->persist ();

  # fetch meshblock admin area database ids
  # this reference keeps admin hierarchy object alive
  my $meshblockIds = $adminHierarchy->meshblocks();

  # parse data next
  for my $key (sort { $a cmp $b } keys %$config) {
    my $topicConfig    = $config->{$key};
    my $meshblockSheet = $topicConfig->{meshblocksheet};

    for my $inputXL (split (/,/, $topicConfig->{'spreadsheets'})) {
      my $inputXLFile = "$opts{input}/$inputXL";

      # instantiate a demographic object per spreadsheet
      my $demographic = Demographic->new ($dbh, $topicConfig, $meshblockIds);

      # parse the demographic data for meshblock sheet
      $demographic->parse ($inputXLFile, $meshblockSheet);
    }
  }

  # commit all spreadsheet data
  $dbh->commit();
};
if ($@) {
  # roll back all loaded data to leave census schema in a consistent state
  $dbh->rollback();

  # reset all serial keys
  my $table;
  my $sth = $dbh->prepare ("SELECT table_name FROM INFORMATION_SCHEMA.tables WHERE table_schema = 'census'");

  $sth->execute();
  $sth->bind_col (1, \$table);

  while ($sth->fetch()) {
    TRACE ("Resetting serial key for table: $table");

    $dbh->do (qq/SELECT pg_catalog.setval(
                   'census./ . $table . qq/_id_seq',
                   (SELECT CASE WHEN MAX(id) IS NULL THEN 1 ELSE MAX(id) - 1 END FROM census.$table),  
                   false)/) || 
      FATAL $DBI::errstr;
  }

  $sth->finish();

  # a failure has occurred, clean up database connection
  $dbh->disconnect();

  exit (1);
}

INFO ("Done, disconnecting");
$dbh->disconnect();

exit (0);
