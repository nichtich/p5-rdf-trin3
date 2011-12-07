package RDF::Trine::Parser::Notation3;

use utf8;
use 5.010;
use strict;
use warnings;
no warnings 'redefine';
no warnings 'once';
use base qw(RDF::Trine::Parser::Turtle);
use Data::UUID;
use RDF::Trine qw();
use RDF::Trine::Statement;
use RDF::Trine::Namespace qw[rdf rdfs owl xsd];
use RDF::Trine::Node;
use RDF::Trine::Error;
use Scalar::Util qw(blessed looks_like_number);

our ($VERSION, $AUTHORITY);

BEGIN 
{
	$VERSION   = '0.136';
	$AUTHORITY = 'cpan:TOBYINK';
	
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

our ($logic);

BEGIN
{
	$logic = RDF::Trine::Namespace->new('http://www.w3.org/2000/10/swap/log#');
}

# Force the default prefix to be bound to the base URI.
sub _Document {
	my $self	= shift;
	my $uri = $self->{'baseURI'};
	local($self->{bindings}{''}) = ($uri =~ /#$/ ? $uri : "$uri#");
	local($self->{'keywords'}) = undef;
	$self->SUPER::_Document(@_);
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
	return 1 if $self->{'tokens'} =~ /(?:true|false)/;
	return 0;
}

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
	if ($self->{tokens} =~ m/^${RDF::Trine::Parser::Turtle::r_resource_test}/) {
		return 1;
	} elsif (defined $self->{'keywords'}
		&& $self->{'tokens'} =~ m/^${RDF::Trine::Parser::Turtle::r_prefixName}/ 
		&& $self->{'tokens'} !~ m/^${RDF::Trine::Parser::Turtle::r_qname}/) {
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
		&& $self->{'tokens'} =~ m/^${RDF::Trine::Parser::Turtle::r_prefixName}/ 
		&& $self->{'tokens'} !~ m/^${RDF::Trine::Parser::Turtle::r_qname}/) {
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

# Subjects can be any node.
sub _subject {
	my $self = shift;
	return $self->_any_node(@_);
}

# Predicates can be any node.
sub _predicate {
	my $self = shift;
	return $self->_any_node(@_);
}

# Objects can be any node.
sub _object {
	my $self = shift;
	return $self->_any_node(@_);
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
	my %old_pragmata = %{ $self->{pragmata} };
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

1;

__END__

=head1 NAME

RDF::Trine::Parser::Notation3 - Notation 3 Parser

=head1 SYNOPSIS

 use RDF::Trine::Parser;
 my $parser     = RDF::Trine::Parser->new( 'Notation3' );
 $parser->parse_into_model( $base_uri, $data, $model );

=head1 METHODS

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

=back

=head1 AUTHOR

Toby Inkster  C<< <tobyink@cpan.org> >>

Based on RDF::Trine::Parser::Turtle by Gregory Todd Williams. 

=head1 COPYRIGHT AND LICENCE

Copyright (c) 2006-2010 Gregory Todd Williams. 

Copyright (c) 2010-2011 Toby Inkster.

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 DISCLAIMER OF WARRANTIES

THIS PACKAGE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.

=cut
