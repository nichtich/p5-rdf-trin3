package RDF::Trine::Parser::Notation3;

use utf8;
use 5.010;
use strict;
use warnings;
no warnings 'redefine';
no warnings 'once';

use Data::UUID;
use Encode;
use Log::Log4perl;
use RDF::Trine qw();
use RDF::Trine::Statement;
use RDF::Trine::Namespace qw[rdf rdfs owl xsd];
use RDF::Trine::Node;
use RDF::Trine::Error;
use Scalar::Util qw(blessed looks_like_number);
use URI;
use URI::Escape qw(uri_unescape);

use base 'RDF::Trine::Parser';

our ($VERSION, $AUTHORITY);

BEGIN 
{
	$VERSION   = '0.206';
	$AUTHORITY = 'cpan:TOBYINK';
}

PARSER_SETUP: {
	my $class = __PACKAGE__;
	$RDF::Trine::Parser::encodings{$class } = 'utf8';
	$RDF::Trine::Parser::canonical_media_types{ $class } = 'text/n3';
	
	$RDF::Trine::Parser::parser_names{$_} = __PACKAGE__
		foreach ('notation3', 'notation 3', 'n3');
	
	$RDF::Trine::Parser::media_types{$_} = __PACKAGE__
		foreach qw(text/n3 text/rdf+n3);
	
	$RDF::Trine::Parser::file_extensions{$_} = __PACKAGE__
		foreach qw(n3);

	$RDF::Trine::Parser::format_uris{$_} = __PACKAGE__
		foreach ('http://www.w3.org/ns/formats/N3');
}

my ($logic, $rdf, $xsd) = do {
	no warnings;
	map { RDF::Trine::Namespace->new($_) }
	qw(
		http://www.w3.org/2000/10/swap/log#
		http://www.w3.org/1999/02/22-rdf-syntax-ns#
		http://www.w3.org/2001/XMLSchema#
	)
};

my $r_boolean       = qr'(?:true|false)'i;
my $r_comment       = qr'#[^\r\n]*';
my $r_decimal       = qr'[+-]?([0-9]+\.[0-9]*|\.([0-9])+)';
my $r_double        = qr'[+-]?([0-9]+\.[0-9]*[eE][+-]?[0-9]+|\.[0-9]+[eE][+-]?[0-9]+|[0-9]+[eE][+-]?[0-9]+)';
my $r_integer       = qr'[+-]?[0-9]+';
my $r_language      = qr'[a-z]+(-[a-z0-9]+)*'i;
my $r_lcharacters   = qr'(?s)[^"\\]*(?:(?:\\.|"(?!""))[^"\\]*)*';
my $r_lcharacters2  = qr{(?s)[^'\\]*(?:(?:\\.|"(?!''))[^'\\]*)*};
my $r_line          = qr'(?:[^\r\n]+[\r\n]+)(?=[^\r\n])';
my $r_nameChar_extra  = qr'[-0-9\x{B7}\x{0300}-\x{036F}\x{203F}-\x{2040}]';
my $r_nameStartChar_minus_underscore  = qr'[A-Za-z\x{00C0}-\x{00D6}\x{00D8}-\x{00F6}\x{00F8}-\x{02FF}\x{0370}-\x{037D}\x{037F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{00010000}-\x{000EFFFF}]';
my $r_scharacters   = qr'[^"\\]*(?:\\.[^"\\]*)*';
my $r_scharacters2  = qr{[^'\\]*(?:\\.[^'\\]*)*};
my $r_ucharacters   = qr'[^>\\]*(?:\\.[^>\\]*)*';
my $r_booltest      = qr'(?:true|false)\b'i;
my $r_nameStartChar = qr/[A-Za-z_\x{00C0}-\x{00D6}\x{00D8}-\x{00F6}\x{00F8}-\x{02FF}\x{0370}-\x{037D}\x{037F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}]/;
my $r_nameChar      = qr/${r_nameStartChar}|[-0-9\x{b7}\x{0300}-\x{036f}\x{203F}-\x{2040}]/;
my $r_prefixName    = qr/(?:(?!_)${r_nameStartChar})($r_nameChar)*/;
my $r_qname         = qr/(?:${r_prefixName})?:/;
my $r_resource_test = qr/<|$r_qname/;
my $r_nameChar_test = qr"(?:$r_nameStartChar|$r_nameChar_extra)";

sub new {
	my $class	= shift;
	my %args	= @_;
	my $prefix	= '';
	if (defined($args{ bnode_prefix })) {
		$prefix	= $args{ bnode_prefix };
	} else {
		$prefix	= $class->new_bnode_prefix();
	}
	my $self	= bless({
					bindings		=> $args{namespaces} || {},
					bnode_id		=> 0,
					bnode_prefix	=> $prefix,
					@_
				}, $class);
	return $self;
}

sub parse {
	my $self	= shift;
	my $uri		= shift;
	my $input	= shift;
	my $handler	= shift;
	local($self->{handle_triple});
	if ($handler) {
		$self->{handle_triple}	= $handler;
	}
	local($self->{baseURI})	= $uri;
	
	$input	= '' unless (defined($input));
	$input	=~ s/^\x{FEFF}//;
	
	local($self->{tokens})	= $input;
	$self->_Document();
	return;
}

sub parse_node {
	my $self	= shift;
	my $input	= shift;
	my $uri		= shift;
	local($self->{handle_triple});
	local($self->{baseURI})	= $uri;
	$input	=~ s/^\x{FEFF}//;
	local($self->{tokens})	= $input;
	return $self->_object();
}

sub _eat_re {
	my $self	= shift;
	my $thing	= shift;
	my $l		= Log::Log4perl->get_logger("rdf.trine.parser.turtle");
	if (not(length($self->{tokens}))) {
		$l->error("no tokens left ($thing)");
		throw RDF::Trine::Error::ParserError -text => "No tokens";
	}
	
	if ($self->{tokens} =~ m/^($thing)/) {
		my $match	= $1;
		substr($self->{tokens}, 0, length($match))	= '';
		return;
	}
	$l->error("Expected ($thing) with remaining: $self->{tokens}");
	throw RDF::Trine::Error::ParserError -text => "Expected: $thing";
}

sub _eat_re_save {
	my $self	= shift;
	my $thing	= shift;
	my $l		= Log::Log4perl->get_logger("rdf.trine.parser.turtle");
	if (not(length($self->{tokens}))) {
		$l->error("no tokens left ($thing)");
		throw RDF::Trine::Error::ParserError -text => "No tokens";
	}
	
	if ($self->{tokens} =~ m/^($thing)/) {
		my $match	= $1;
		substr($self->{tokens}, 0, length($match))	= '';
		return $match;
	}
	$l->error("Expected ($thing) with remaining: $self->{tokens}");
	throw RDF::Trine::Error::ParserError -text => "Expected: $thing";
}

sub _eat {
	my $self	= shift;
	my $thing	= shift;
	my $l		= Log::Log4perl->get_logger("rdf.trine.parser.turtle");
	if (not(length($self->{tokens}))) {
		$l->error("no tokens left ($thing)");
		throw RDF::Trine::Error::ParserError -text => "No tokens";
	}
	
	### thing is a string
	if (substr($self->{tokens}, 0, length($thing)) eq $thing) {
		substr($self->{tokens}, 0, length($thing))	= '';
		return;
	} else {
		$l->logcluck("expected: $thing, got: $self->{tokens}");
		throw RDF::Trine::Error::ParserError -text => "Expected: $thing";
	}
}

sub _test {
	my $self	= shift;
	my $thing	= shift;
	if (substr($self->{tokens}, 0, length($thing)) eq $thing) {
		return 1;
	} else {
		return 0;
	}
}

sub _triple {
	my $self	= shift;
	my $s		= shift;
	my $p		= shift;
	my $o		= shift;
	foreach my $n ($s, $p, $o) {
		unless ($n->isa('RDF::Trine::Node')) {
			throw RDF::Trine::Error::ParserError;
		}
	}
	
	if ($self->{canonicalize})
	{
		foreach my $n ($s, $p, $o)
		{
			if ($n->isa('RDF::Trine::Node::Literal') and $n->has_datatype)
			{
				my $value	= $n->literal_value;
				my $dt		= $n->literal_datatype;
				my $canon	= RDF::Trine::Node::Literal->canonicalize_literal_value($value, $dt, 1);
				$n	= RDF::Trine::Node::Literal->new($canon, undef, $dt);
			}
		}
	}
	
	my $st	= RDF::Trine::Statement->new( $s, $p, $o );
	if (my $code = $self->{handle_triple}) {
		$code->( $st );
	}
	
	my $count	= ++$self->{triple_count};
}

# Force the default prefix to be bound to the base URI.
sub _Document {
	my $self	= shift;
	my $uri = $self->{'baseURI'};
	local($self->{bindings}{''}) = ($uri =~ /#$/ ? $uri : "$uri#");
	local($self->{'keywords'}) = undef;
	while ($self->_statement_test()) {
		$self->_statement();
	}
}

sub _statement_test {
	my $self	= shift;
	if (length($self->{tokens})) {
		return 1;
	} else {
		return 0;
	}
}

sub _statement {
	my $self	= shift;
	if ($self->_directive_test()) {
		$self->_directive();
		$self->__consume_ws();
		$self->_eat('.');
		$self->__consume_ws();
	} elsif ($self->_triples_test()) {
		$self->_triples();
		$self->__consume_ws();
		$self->_eat('.');
		$self->__consume_ws();
	}  else {
		$self->_ws();
		$self->__consume_ws();
	}
}

sub _directive_test {
	my $self	= shift;
	### between directive | triples | ws
	### directives must start with @, triples must not
	if ($self->__startswith('@')) {
		return 1;
	} else {
		return 0;
	}
}

# N3-specific directives
sub _directive {
	my $self	= shift;
	### prefixID | base
	if ($self->_prefixID_test()) {
		$self->_prefixID();
	} elsif ($self->_quantifier_test()) {
		$self->_quantifier();
	} elsif ($self->_keywords_test()) {
		$self->_keywords();
	} else {
		$self->_base();
	}
}

sub _prefixID_test {
	my $self	= shift;
	### between prefixID | base. prefixID is @prefix, base is @base
	if ($self->__startswith('@prefix')) {
		return 1;
	} else {
		return 0;
	}
}

sub _prefixID {
	my $self	= shift;
	### '@prefix' ws+ prefixName? ':' ws+ uriref
	$self->_eat('@prefix');
	$self->_ws();
	$self->__consume_ws();
	
	my $prefix;
	if ($self->_prefixName_test()) {
		$prefix = $self->_prefixName();
	} else {
		$prefix	= '';
	}
	
	$self->_eat(':');
	$self->_ws();
	$self->__consume_ws();
	
	my $uri = $self->_uriref();
	$self->{bindings}{$prefix}	= $uri;
	
	if (blessed(my $ns = $self->{namespaces})) {
		unless ($ns->namespace_uri($prefix)) {
			$ns->add_mapping( $prefix => $uri );
		}
	}
}



sub _base {
	my $self	= shift;
	### '@base' ws+ uriref
	$self->_eat('@base');
	$self->_ws();
	$self->__consume_ws();
	my $uri	= $self->_uriref();
	if (ref($uri)) {
		$uri	= $uri->uri_value;
	}
	$self->{baseURI}	=	$self->_join_uri($self->{baseURI}, $uri);
}

# Allow any type of node to begin a set of triples.
sub _triples_test {
	my $self = shift;
	return 1 if $self->_resource_test;
	return 1 if $self->_blank_test;
	return 1 if $self->_variable_test;
	return 1 if $self->_formula_test;
	return 1 if $self->_quotedString_test;
	return 1 if $self->_double_test;
	return 1 if $self->_decimal_test;
	return 1 if $self->_integer_test;
	return 1 if $self->{'tokens'} =~ m{^$r_booltest};
	return 0;
}

*_predicate_test = \&_triples_test;

# Need to override _triples and _predicateObjectList to implement "is ... of".
sub _triples {
	my $self	= shift;
	### subject ws+ predicateObjectList
	my $subj	= $self->_subject();
	$self->_ws();
	$self->__consume_ws;
	foreach my $data ($self->_predicateObjectList()) {
		my ($pred, $objt, $direction)	= @$data;
		# direction: 0=forwards; 1=backwards.
		if ($direction) {
			$self->_triple( $objt, $pred, $subj );
		} else {
			$self->_triple( $subj, $pred, $objt );
		}
	}
}

sub _objectList {
	my $self	= shift;
	### object (ws* ',' ws* object)*
	my @list;
	push(@list, $self->_object());
	$self->__consume_ws();
	while ($self->_test(',')) {
		$self->__consume_ws();
		$self->_eat(',');
		$self->__consume_ws();
		push(@list, $self->_object());
		$self->__consume_ws();
	}
	return @list;
}

# Notation 3 has additional keywords
sub _verb_test {
	my $self	= shift;
	return 0 unless (length($self->{tokens}));
	return 1 if ($self->{tokens} =~ /^a\b/);
	return 1 if ($self->{tokens} =~ /^=>\b/);
	return 1 if ($self->{tokens} =~ /^<=\b/);
	return 1 if ($self->{tokens} =~ /^=\b/);
	return $self->_predicate_test();
}

# Verb now also returns directionality.
sub _verb {
	my $self	= shift;
	if ($self->_test('<=')) {
		$self->_eat('<=');
		return [ $logic->implies , 1 ];
	} elsif ($self->_test('=>')) {
		$self->_eat('=>');
		return [ $logic->implies , 0 ];
	} elsif ($self->_test('=')) {
		$self->_eat('=');
		return [ $owl->sameAs, 0 ];
	} elsif ($self->{tokens} =~ m'^a\b') {
		$self->_eat('a');
		return [ $rdf->type , 0 ];
	} elsif ($self->_predicate_test()) {
		return [ $self->_predicate(), 0] ;
	} else {
		$self->_eat('<PREDICATE>');
	}
}

sub _comment {
	my $self	= shift;
	### '#' ( [^#xA#xD] )*
	$self->_eat_re($r_comment);
	return 1;
}

sub _literal {
	my $self	= shift;
	### quotedString ( '@' language )? | datatypeString | integer | 
	### double | decimal | boolean
	### datatypeString = quotedString '^^' resource      
	### (so we change this around a bit to make it parsable without a huge 
	### multiple lookahead)
	
	if ($self->_quotedString_test()) {
		my $value = $self->_quotedString();
		if ($self->_test('@')) {
			$self->_eat('@');
			my $lang = $self->_language();
			return $self->__Literal($value, $lang);
		} elsif ($self->_test('^^')) {
			$self->_eat('^^');
			my $dtype = $self->_resource();
			return $self->_typed($value, $dtype);
		} else {
			return $self->__Literal($value);
		}
	} elsif ($self->_double_test()) {
		return $self->_double();
	} elsif ($self->_decimal_test()) {
		return $self->_decimal();
	} elsif ($self->_integer_test()) {
		return $self->_integer();
	} else {
		return $self->_boolean();
	}
}

sub _double_test {
	my $self	= shift;
	if ($self->{tokens} =~ /^$r_double/) {
		return 1;
	} else {
		return 0;
	}
}

sub _double {
	my $self	= shift;
	### ('-' | '+') ? ( [0-9]+ '.' [0-9]* exponent | '.' ([0-9])+ exponent 
	### | ([0-9])+ exponent )
	### exponent = [eE] ('-' | '+')? [0-9]+
	my $token	= $self->_eat_re_save( $r_double );
	return $self->_typed( $token, $xsd->double );
}

sub _decimal_test {
	my $self	= shift;
	if ($self->{tokens} =~ /^$r_decimal/) {
		return 1;
	} else {
		return 0;
	}
}

sub _decimal {
	my $self	= shift;
	### ('-' | '+')? ( [0-9]+ '.' [0-9]* | '.' ([0-9])+ | ([0-9])+ )
	my $token	= $self->_eat_re_save( $r_decimal );
	return $self->_typed( $token, $xsd->decimal );
}

sub _integer_test {
	my $self	= shift;
	if ($self->{tokens} =~ /^$r_integer/) {
		return 1;
	} else {
		return 0;
	}
}

sub _integer {
	my $self	= shift;
	### ('-' | '+')? ( [0-9]+ '.' [0-9]* | '.' ([0-9])+ | ([0-9])+ )
	my $token	= $self->_eat_re_save( $r_integer );
	return $self->_typed( $token, $xsd->integer );
}

sub _boolean {
	my $self	= shift;
	### 'true' | 'false'
	my $token	= $self->_eat_re_save( $r_boolean );
	return $self->_typed( lc $token, $xsd->boolean );
}

sub _blank_test {
	my $self	= shift;
	### between this and literal. urgh!
	### this can start with...
	### _ | [ | (
	### literal can start with...
	### * " | + | - | digit | t | f
	if ($self->{tokens} =~ m/^[_[(]/) {
		return 1;
	} else {
		return 0;
	}
}

sub _blank {
	my $self	= shift;
	### nodeID | '[]' | '[' ws* predicateObjectList ws* ']' | collection
	if ($self->_nodeID_test) {
		return $self->__bNode( $self->__anonimize_bnode_id( $self->_nodeID() ) );
	} elsif ($self->_test('[]')) {
		$self->_eat('[]');
		return $self->__bNode( $self->__generate_bnode_id() );
	} elsif ($self->_test('[')) {
		$self->_eat('[');
		my $subj	= $self->__bNode( $self->__generate_bnode_id() );
		$self->__consume_ws();
		foreach my $data ($self->_predicateObjectList()) {
			my ($pred, $objt)	= @$data;
			$self->_triple( $subj, $pred, $objt );
		}
		$self->__consume_ws();
		$self->_eat(']');
		return $subj;
	} else {
		return $self->_collection();
	}
}

sub _itemList_test {
	my $self	= shift;
	### between this and whitespace or ')'
	return 0 unless (length($self->{tokens}));
	if ($self->{tokens} !~ m/^[\r\n\t #)]/) {
		return 1;
	} else {
		return 0;
	}
}

sub _itemList {
	my $self	= shift;
	### object (ws+ object)*
	my @list;
	push(@list, $self->_object());
	while ($self->_ws_test()) {
		$self->__consume_ws();
		if (not $self->_test(')')) {
			push(@list, $self->_object());
		}
	}
	return @list;
}

sub _collection {
	my $self	= shift;
	### '(' ws* itemList? ws* ')'
	my $b	= $self->__bNode( $self->__generate_bnode_id() );
	my ($this, $rest)	= ($b, undef);
	$self->_eat('(');
	$self->__consume_ws();
	if ($self->_itemList_test()) {
#		while (my $objt = $self->_itemList()) {
		foreach my $objt ($self->_itemList()) {
			if (defined($rest)) {
				$this	= $self->__bNode( $self->__generate_bnode_id() );
				$self->_triple( $rest, $rdf->rest, $this)
			}
			$self->_triple( $this, $rdf->first, $objt );
			$rest = $this;
		}
	}
	if (defined($rest)) {
		$self->_triple( $rest, $rdf->rest, $rdf->nil );
	} else {
		$b = $rdf->nil;
	}
	$self->__consume_ws();
	$self->_eat(')');
	return $b;
}

sub _ws_test {
	my $self	= shift;
	unless (length($self->{tokens})) {
		return 0;
	}
	
	if ($self->{tokens} =~ m/^[\t\r\n #]/) {
		return 1;
	} else {
		return 0;
	}
}

sub _ws {
	my $self	= shift;
	### #x9 | #xA | #xD | #x20 | comment
	if ($self->_test('#')) {
		$self->_comment();
	} else {
		my $ws	= $self->_eat_re_save( qr/[\n\r\t ]+/ );
		unless ($ws =~ /^[\n\r\t ]/) {
			throw RDF::Trine::Error::ParserError -text => 'Not whitespace';
		}
	}
}

sub _nodeID_test {
	my $self	= shift;
	### between this (_) and []
	if (substr($self->{tokens}, 0, 1) eq '_') {
		return 1;
	} else {
		return 0;
	}
}

sub _nodeID {
	my $self	= shift;
	### '_:' name
	$self->_eat('_:');
	return $self->_name();
}

sub _qname {
	my $self	= shift;
	### prefixName? ':' name?
	my $prefix	= ($self->{tokens} =~ /^$r_nameStartChar_minus_underscore/) ? $self->_prefixName() : '';
	$self->_eat(':');
	my $name	= ($self->{tokens} =~ /^$r_nameStartChar/) ? $self->_name() : '';
	unless (exists $self->{bindings}{$prefix}) {
		throw RDF::Trine::Error::ParserError -text => "Undeclared prefix $prefix";
	}
	my $uri		= $self->{bindings}{$prefix};
	return $uri . $name
}

sub _uriref_test {
	my $self	= shift;
	### between this and qname
	if ($self->__startswith('<')) {
		return 1;
	} else {
		return 0;
	}
}

sub _uriref {
	my $self	= shift;
	### '<' relativeURI '>'
	$self->_eat('<');
	my $value	= $self->_relativeURI();
	$self->_eat('>');
	my $uri	= uri_unescape(encode_utf8($value));
	my $uni	= decode_utf8($uri);
	return $uni;
}

sub _language {
	my $self	= shift;
	### [a-z]+ ('-' [a-z0-9]+ )*
	my $token	= $self->_eat_re_save( $r_language );
	return $token;
}

sub _nameStartChar_test {
	my $self	= shift;
	if ($self->{tokens} =~ /^$r_nameStartChar/) {
		return 1;
	} else {
		return 0;
	}
}

sub _nameStartChar {
	my $self	= shift;
	### [A-Z] | "_" | [a-z] | [#x00C0-#x00D6] | [#x00D8-#x00F6] | 
	### [#x00F8-#x02FF] | [#x0370-#x037D] | [#x037F-#x1FFF] | [#x200C-#x200D] 
	### | [#x2070-#x218F] | [#x2C00-#x2FEF] | [#x3001-#xD7FF] | 
	### [#xF900-#xFDCF] | [#xFDF0-#xFFFD] | [#x10000-#xEFFFF]
	my $nc	= $self->_eat_re_save( $r_nameStartChar );
	return $nc;
}

sub _nameChar_test {
	my $self	= shift;
	if ($self->{tokens} =~ /^$r_nameStartChar/) {
		return 1;
	} elsif ($self->{tokens} =~ /^$r_nameChar_extra/) {
		return 1;
	} else {
		return 0;
	}
}

sub _nameChar {
	my $self	= shift;
	### nameStartChar | '-' | [0-9] | #x00B7 | [#x0300-#x036F] | 
	### [#x203F-#x2040]
#	if ($self->_nameStartChar_test()) {
	if ($self->{tokens} =~ /^$r_nameStartChar/) {
		my $nc	= $self->_nameStartChar();
		return $nc;
	} else {
		my $nce	= $self->_eat_re_save( $r_nameChar_extra );
		return $nce;
	}
}

sub _name {
	my $self	= shift;
	### nameStartChar nameChar*
	my $name	= $self->_eat_re_save( qr/^${r_nameStartChar}(${r_nameStartChar}|${r_nameChar_extra})*/ );
	return $name;
}

sub _prefixName_test {
	my $self	= shift;
	### between this and colon
	if ($self->{tokens} =~ /^$r_nameStartChar_minus_underscore/) {
		return 1;
	} else {
		return 0;
	}
}

sub _prefixName {
	my $self	= shift;
	### ( nameStartChar - '_' ) nameChar*
	my @parts;
	my $nsc	= $self->_eat_re_save( $r_nameStartChar_minus_underscore );
	push(@parts, $nsc);
#	while ($self->_nameChar_test()) {
	while ($self->{tokens} =~ /^$r_nameChar_test/) {
		my $nc	= $self->_nameChar();
		push(@parts, $nc);
	}
	return join('', @parts);
}

sub _relativeURI {
	my $self	= shift;
	### ucharacter*
	my $token	= $self->_eat_re_save( $r_ucharacters );
	return $token;
}

sub _quotedString_test {
	my $self	= shift;
	if (substr($self->{tokens}, 0, 1) eq '"') {
		return 1;
	} elsif (substr($self->{tokens}, 0, 1) eq "'") {
		return 1;
	} else {
		return 0;
	}
}

sub _quotedString {
	my $self	= shift;
	### string | longString
	if ($self->_longString_test()) {
		return $self->_longString();
	} else {
		return $self->_string();
	}
}

sub _string {
	my $self	= shift;
	### #x22 scharacter* #x22
	my $value;
	if ($self->__startswith( '"' )) {
		$self->_eat('"');
		$value	= $self->_eat_re_save( $r_scharacters );
		$self->_eat('"');
	} else {
		$self->_eat("'");
		$value	= $self->_eat_re_save( $r_scharacters2 );
		$self->_eat("'");
	}
	my $string	= $self->_parse_short( $value );
	return $string;
}

sub _longString_test {
	my $self	= shift;
	if ($self->__startswith( '"""' )) {
		return 1;
	} elsif ($self->__startswith( "'''" )) {
		return 1;
	} else {
		return 0;
	}
}

sub _longString {
	my $self	= shift;
      # #x22 #x22 #x22 lcharacter* #x22 #x22 #x22
	my $value;
	if ($self->__startswith( '"""' )) {
		$self->_eat('"""');
		$value = $self->_eat_re_save( $r_lcharacters );
		$self->_eat('"""');
	} else {
		$self->_eat("'''");
		$value = $self->_eat_re_save( $r_lcharacters2 );
		$self->_eat("'''");
	}
	my $string	= $self->_parse_long( $value );
	return $string;
}

################################################################################

{
	my %easy = (
		q[\\]   =>  qq[\\],
		r       =>  qq[\r],
		n       =>  qq[\n],
		t       =>  qq[\t],
		q["]    =>  qq["],
	);
	
	sub _parse_short {
		my $self = shift;
		my $s    = shift;
		return '' unless length($s);

		$s =~ s{ \\ ( [\\tnr"] | u.{4} | U.{8} ) }{
			if (exists $easy{$1})
			{
				$easy{$1};
			}
			else
			{
				my $hex = substr($1, 1);
				die "invalid hexadecimal escape: $hex"
					unless $hex =~ m{^[0-9A-Fa-f]+$};
				chr(hex($hex));
			}
		}gex;
		
		return $s;
	}

	# they're the same
	*_parse_long = \&_parse_short;
}

sub _join_uri {
	my $self	= shift;
	my $base	= shift;
	my $uri		= shift;
	if ($base eq $uri) {
		return $uri;
	}
	return URI->new_abs( $uri, $base );
}

sub _typed {
	my $self		= shift;
	my $value		= shift;
	my $type		= shift;
	my $datatype	= $type->uri_value;
	
	if ($datatype eq "${xsd}decimal") {
		$value	=~ s/[.]0+$//;
		if ($value !~ /[.]/) {
			$value = $value . '.0';
		}
	}
	
	return $self->__Literal($value, undef, $datatype)
}

sub __anonimize_bnode_id {
	my $self	= shift;
	my $id		= shift;
	if (my $aid = $self->{ bnode_map }{ $id }) {
		return $aid;
	} else {
		my $aid	= $self->__generate_bnode_id;
		$self->{ bnode_map }{ $id }	= $aid;
		return $aid;
	}
}

sub __generate_bnode_id {
	my $self	= shift;
	my $id		= $self->{ bnode_id }++;
	return 'r' . $self->{bnode_prefix} . 'r' . $id;
}

sub __consume_ws {
	my $self	= shift;
	while ($self->{tokens} =~ m/^[\t\r\n #]/) {
		$self->_ws()
	}
}

sub __URI {
	my $self	= shift;
	my $uri		= shift;
	my $base	= shift;
	return RDF::Trine::Node::Resource->new( $uri, $base )
}

sub __bNode {
	my $self	= shift;
	return RDF::Trine::Node::Blank->new( @_ )
}

sub __Literal {
	my $self	= shift;
	my $lit = RDF::Trine::Node::Literal->new( @_ );
	
	no warnings;
	if (!$self->{suspend_callback}
	and $lit->has_datatype
	and my $code = $self->{datatype_callback}{$lit->literal_datatype})
	{
		my $triple_callback = sub {
			my ($s, $p, $o) = shift->nodes;
			$self->_triple($s, $p, $o);
		};
		my $return = $code->($lit, $triple_callback);
		if (blessed $return and $return->isa('RDF::Trine::Node'))
		{
			return $return;
		}
	}
	
	return $lit;
}

sub __startswith {
	my $self	= shift;
	my $thing	= shift;
	if (substr($self->{tokens}, 0, length($thing)) eq $thing) {
		return 1;
	} else {
		return 0;
	}
}

sub _unescape {
	my $str = shift;
	my @chars = split(//, $str);
	my $us	= '';
	while(defined(my $char = shift(@chars))) {
		if($char eq '\\') {
			if(($char = shift(@chars)) eq 'u') {
				my $i = 0;
				for(; $i < 4; $i++) {
					unless($chars[$i] =~ /[0-9a-fA-F]/){
						last;
					}				
				}
				if($i == 4) {
					my $hex = join('', splice(@chars, 0, 4));
					my $cp = hex($hex);
					my $char	= chr($cp);
					$us .= $char;
				}
				else {
					$us .= 'u';
				}
			}
			else {
				$us .= '\\' . $char;
			}
		}
		else {
			$us .= $char;
		}
	}
	return $us;
}


sub _keywords_test {
	my $self = shift;
	return $self->__startswith('@keywords');
}

sub _keywords {
	my $self	= shift;
	
	$self->_eat('@keywords');
	$self->_ws();
	$self->__consume_ws();
	
	my @kw;
	push @kw, $self->_name();
	$self->__consume_ws();
	
	while (! $self->_test('.')) {
		$self->_eat(',');
		$self->__consume_ws();
		push @kw, $self->_name();
		$self->__consume_ws();
	}
	
	$self->{'keywords'} = \@kw;
	return @kw;
}

sub _quantifier_test {
	my $self = shift;
	return $self->__startswith('@forAll') || $self->__startswith('@forSome');
}

sub _quantifier {
	my $self	= shift;
	
	my $quantifier;
	if ($self->_test('@forSome')) {
		$quantifier = 'forSome';
		$self->_eat('@forSome');
		$self->_ws();
		$self->__consume_ws();
	} else {
		$quantifier = 'forAll';
		$self->_eat('@forAll');
		$self->_ws();
		$self->__consume_ws();
	}
	
	my @terms;
	push @terms, $self->_resource();
	$self->__consume_ws();
	
	while (! $self->_test('.')) {
		$self->_eat(',');
		$self->__consume_ws();
		push @terms, $self->_resource();
		$self->__consume_ws();
	}
	
	my $code = $self->{'handle_'.lc $quantifier};
	if (ref $code eq 'CODE') {
		foreach my $resource (@terms) {
			$code->($resource);
		}
	} else {
		warn "Encountered \@${quantifier} but no handler set up";
	}
	
	return { $quantifier => [@terms] };
}

sub forAll {
	my $self	= shift;
	if (@_) {
		$self->{handle_forall} = shift;
	}
	return $self->{handle_forall};
}

sub forSome {
	my $self	= shift;
	if (@_) {
		$self->{handle_forsome} = shift;
	}
	return $self->{handle_forsome};
}


sub _predicateObjectList {
	my $self	= shift;
	
	if ($self->{'tokens'} =~ /^is\b/)
	{
		$self->_eat('is');
		$self->__consume_ws;
	}
	elsif ($self->{'tokens'} =~ /^has\b/
	and grep {$_ eq 'has'} @{$self->{'keywords'}})
	{
		$self->_eat('has');
		$self->__consume_ws;
	}	
	
	my ($pred, $reverse) = @{ $self->_verb() };
	$self->_ws();
	$self->__consume_ws();
	
	if ($self->{'tokens'} =~ /^of\b/)
	{
		$reverse = !$reverse;
		$self->_eat('of');
		$self->__consume_ws;
	}
	
	my @list;
	foreach my $objt ($self->_objectList()) {
		push(@list, [$pred, $objt, $reverse]);
	}
	
	while ($self->{tokens} =~ m/^[\t\r\n #]*;/) {
		$self->__consume_ws();
		$self->_eat(';');
		$self->__consume_ws();
		if ($self->_verb_test()) { # @@
			if ($self->{'tokens'} =~ /^is\b/)
			{
				$self->_eat('is');
				$self->__consume_ws;
			}
			my ($pred, $reverse) = @{ $self->_verb() };
			$self->_ws();
			$self->__consume_ws();
			if ($self->{'tokens'} =~ /^of\b/)
			{
				$reverse = !$reverse;
				$self->_eat('of');
				$self->__consume_ws;
			}
			foreach my $objt ($self->_objectList()) {
				push(@list, [$pred, $objt, $reverse]);
			}
		} else {
			last
		}
	}
	
	return @list;
}

# Notation 3 allows keywords to be treated as resources in the default namespace... sometimes.
sub _resource_test {
	my $self	= shift;
	return 0 unless (length($self->{tokens}));
	return 0 if $self->{tokens} =~ m/^(true|false)\b/;
	if ($self->{tokens} =~ m/^${r_resource_test}/) {
		return 1;
	} elsif (defined $self->{'keywords'}
		&& $self->{'tokens'} =~ m/^${r_prefixName}/ 
		&& $self->{'tokens'} !~ m/^${r_qname}/) {
		return 1;
	} else {
		return 0;
	}
}

sub _resource {
	my $self	= shift;
	if ($self->_uriref_test()) {
		return $self->__URI($self->_uriref(), $self->{baseURI});
	} elsif (defined $self->{'keywords'}
		&& $self->{'tokens'} =~ m/^${r_prefixName}/ 
		&& $self->{'tokens'} !~ m/^${r_qname}/) {
		my $name = $self->_name();
		if (grep { lc $name eq lc $_ } @{$self->{'keywords'}})
		{
			throw RDF::Trine::Error::ParserError -text => "Unexpected keyword: $name.";
		}
		$self->{tokens} = ':'.$name.$self->{tokens}; # cheat!
		my $qname	= $self->_qname();
		my $base	= $self->{baseURI};
		return $self->__URI($qname, $base);
	} else {
		my $qname	= $self->_qname();
		my $base	= $self->{baseURI};
		return $self->__URI($qname, $base);
	}
}

# What do I mean by "any node"?.
sub _any_node {
	my $self = shift;
	my $ignore_paths = shift;
	
	my $node;
	if (length($self->{tokens}) and $self->_resource_test()) {
		$node = $self->_resource();
	} elsif ($self->_blank_test()) {
		$node = $self->_blank();
	} elsif ($self->_formula_test()) {
		$node = $self->_formula();
	} elsif ($self->_variable_test()) {
		$node = $self->_variable();
	} else {
		$node = $self->_literal();
	}
	
	return $node if $ignore_paths;
	
	while ($self->_test('^') || $self->_test('!')) {
		if ($self->_test('^')) {
			$self->_eat('^');
			my $pred = $self->_predicate(1);
			my $subj = $self->__bNode( $self->__generate_bnode_id() );
			$self->_triple( $subj, $pred, $node );
			$node = $subj;
		} elsif ($self->_test('!')) {
			$self->_eat('!');
			my $pred = $self->_predicate(1);
			my $objt = $self->__bNode( $self->__generate_bnode_id() );
			$self->_triple( $node, $pred, $objt );
			$node = $objt;
		}
	}
	
	return $node;
}

*_subject   = \&_any_node;
*_predicate = \&_any_node;
*_object    = \&_any_node;

# Support variables
sub _variable_test {
	my $self = shift;
	return $self->{'tokens'} =~ /^\?/;
}

sub _variable {
	my $self = shift;
	$self->_eat('?');
	return RDF::Trine::Node::Variable->new( $self->_name() );
}

# Support formulae
sub _formula_test {
	my $self = shift;
	return $self->{'tokens'} =~ /^\{/;
}

sub _formula {
	my $self = shift;
	
	# blank node identifiers don't carry into formulae.
	my $uuid = Data::UUID->new->create_str;
	$uuid    =~ s/-//g;
	local($self->{bnode_prefix}) = 'G'. $uuid;
	local($self->{bnode_map})    = {};
	local($self->{bnode_id})     = 0;

	# Formula pragmata is a clone of current pragmata, so that it can't leak.
	my %old_pragmata = %{ $self->{pragmata} || {} };
	local($self->{pragmata}) = { %old_pragmata };

	# divert triples inside the formula into @triples.
	my @triples;
	my @forAll;
	my @forSome;
	local($self->{handle_triple})  = sub { push @triples, $_[0]; };
	local($self->{handle_forsome}) = sub { push @forSome, $_[0]; };
	local($self->{handle_forall})  = sub { push @forAll, $_[0]; };
	
	$self->_eat('{');
	
	while (!$self->_test('}'))
	{
		$self->__consume_ws;
		
		STATEMENTLIST:
		while ($self->_triples_test || $self->_directive_test())
		{
			if ($self->_triples_test)
			{
				$self->_triples;
				$self->__consume_ws;
			}
			else
			{
				$self->_directive();
				$self->__consume_ws();
			}
			
			if ($self->_test('.'))
			{
				$self->_eat('.');
				$self->__consume_ws;
				last STATEMENTLIST if $self->_test('}');
			}
			elsif ($self->_test('}'))
			{
				last STATEMENTLIST;
			}
			else
			{
				throw RDF::Trine::Error::ParserError -text => "Unexpected content in formula: ".$self->{tokens};
			}
		}
	}
	$self->_eat('}');
	
	# return a formula. can it really be that easy?
	#warn Dumper([@triples]) . " being saved as a Formula\n";
	my $formula = RDF::Trine::Node::Formula->new( RDF::Trine::Pattern->new(@triples) );
	#warn Dumper($formula);
	$formula->[3] = \@forAll;
	$formula->[4] = \@forSome;
	return $formula;
}

sub parse_formula {
	my $self  = shift;
	my $uri   = shift;
	my $input = shift;
	
	local($self->{baseURI}) = $uri;
	local($self->{tokens})  = "{ ".$input." }";
	
	return $self->_formula;
}

sub namespaces {
    $_[0]->{bindings};
}

1;

__END__

=head1 NAME

RDF::Trine::Parser::Notation3 - Notation 3 Parser

=head1 SYNOPSIS

 use RDF::Trine::Parser;
 my $parser     = RDF::Trine::Parser->new( 'Notation3' );
 $parser->parse_into_model( $base_uri, $data, $model );

=head1 DESCRIPTION

This module provides a Notation 3 parser for RDF::Trine.

=head2 Methods

This package exposes the standard RDF::Trine::Parser methods, plus:

=over

=item C<< forAll($handler) >>

Sets a callback handler for @forAll directives found in the top-level
graph. (@forAll found in nested formulae will not be passed to this callback.)

The handler should be a coderef that takes a single argument: an
RDF::Trine::Node::Resource.

If you do not set a handler, a warning will be issued when this directive
are encountered in the top level graph, but parsing will continue.

=item C<< forSome($handler) >>

As C<forAll> but handles @forSome directives.

=item C<< parse_formula($base, $input) >>

Returns an RDF::Trine::Node::Formula object representing the Notation 3
formula given as $input. $input should not include the "{"..."}" wrappers.

=item C<< namespaces >>

Returns defined namespaces as (possibly blessed) hash reference. Namespaces can
be predefined with the constructor option C<namespaces>.

=back

=head2 Datatype Callbacks

The constructor accepts a hashref of callbacks associated with datatypes,
which will be triggered after a literal has been parsed with that datatype.
Let's imagine that you want to replace all xsd:integer literals with
URIs like C<< http:;//example.net/numbers/123 >>...

 my $parser = RDF::Trine::Parser::Notation3->new(
   datatype_callback => {
     'http://www.w3.org/2001/XMLSchema#integer' => sub {
       my ($lit, $tr_hnd) = @_;
       return RDF::Trine::Node::Resource->new(
         'http:;//example.net/numbers/' . $lit->literal_value
       );
     },
   },
 );

Note the second argument passed to the callback C<< $tr_hnd >>. We don't
use it here, but it's a coderef that can be called with RDF::Trine::Statement
objects to add additional triples to the graph being parsed.

This facility, combined with shortcuts from
L<RDF::Trine::Parser::ShorthandRDF> is pretty useful for creating
domain-specific languages.

=head1 BUGS

Please report any bugs to
L<http://rt.cpan.org/Dist/Display.html?Queue=RDF-TriN3>.

=head1 SEE ALSO

L<RDF::Trine::Parser::NTriples>,
L<RDF::Trine::Parser::Turtle>,
L<RDF::Trine::Parser::ShorthandRDF>.

=head1 AUTHOR

Toby Inkster  C<< <tobyink@cpan.org> >>

Based on RDF::Trine::Parser::Turtle by Gregory Todd Williams. 

=head1 COPYRIGHT AND LICENCE

Copyright (c) 2006-2010 Gregory Todd Williams. 

Copyright (c) 2010-2012 Toby Inkster.

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 DISCLAIMER OF WARRANTIES

THIS PACKAGE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.

=cut
