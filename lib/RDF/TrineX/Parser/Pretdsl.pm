package RDF::TrineX::Parser::Pretdsl;

our $AUTHORITY = 'cpan:TOBYINK';
our $VERSION   = '0.140';

our $PROFILE = <<'PRETDSL_PROFILE';

# RDFa 1.1 prefixes
@prefix grddl:    <http://www.w3.org/2003/g/data-view#> .
@prefix ma:       <http://www.w3.org/ns/ma-ont#> .
@prefix owl:      <http://www.w3.org/2002/07/owl#> .
@prefix rdf:      <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
@prefix rdfa:     <http://www.w3.org/ns/rdfa#> .
@prefix rdfs:     <http://www.w3.org/2000/01/rdf-schema#> .
@prefix rif:      <http://www.w3.org/2007/rif#> .
@prefix skos:     <http://www.w3.org/2004/02/skos/core#> .
@prefix skosxl:   <http://www.w3.org/2008/05/skos-xl#> .
@prefix wdr:      <http://www.w3.org/2007/05/powder#> .
@prefix void:     <http://rdfs.org/ns/void#> .
@prefix wdrs:     <http://www.w3.org/2007/05/powder-s#> .
@prefix xhv:      <http://www.w3.org/1999/xhtml/vocab#> .
@prefix xml:      <http://www.w3.org/XML/1998/namespace> .
@prefix xsd:      <http://www.w3.org/2001/XMLSchema#> .
@prefix cc:       <http://creativecommons.org/ns#> .
@prefix ctag:     <http://commontag.org/ns#> .
@prefix dc:       <http://purl.org/dc/terms/> .
@prefix dcterms:  <http://purl.org/dc/terms/> .
@prefix foaf:     <http://xmlns.com/foaf/0.1/> .
@prefix gr:       <http://purl.org/goodrelations/v1#> .
@prefix ical:     <http://www.w3.org/2002/12/cal/icaltzd#> .
@prefix og:       <http://ogp.me/ns#> .
@prefix rev:      <http://purl.org/stuff/rev#> .
@prefix sioc:     <http://rdfs.org/sioc/ns#> .
@prefix v:        <http://rdf.data-vocabulary.org/#> .
@prefix vcard:    <http://www.w3.org/2006/vcard/ns#> .
@prefix schema:   <http://schema.org/> .

# Additional useful vocabularies
@prefix cpant:       <http://purl.org/NET/cpan-uri/terms#>.
@prefix dbug:        <http://ontologi.es/doap-bugs#> .
@prefix dcs:         <http://ontologi.es/doap-changeset#> .
@prefix doap:        <http://usefulinc.com/ns/doap#> .
@prefix earl:        <http://www.w3.org/ns/earl#> .
@prefix nfo:         <http://www.semanticdesktop.org/ontologies/2007/03/22/nfo#> .
@prefix pretdsl:     <http://ontologi.es/pretdsl#> .
@prefix pretdsl-dt:  <http://ontologi.es/pretdsl#dt/> .

# Useful XSD datatypes
@dtpattern
	"[0-9]{4}-[0-9]{2}-[0-9]{2}"
	<http://www.w3.org/2001/XMLSchema#date> .
@dtpattern
	"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{4}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})?"
	<http://www.w3.org/2001/XMLSchema#dateTime> .

# Other datatype shorthands
@pattern
	"`(?<x>.+?)`"
	"$x"^^pretdsl-dt:PerlResourceIdentifier .
@pattern
	"d`(?<x>.+?)`"
	"$x"^^pretdsl-dt:Distribution .
@pattern
	"r`(?<x>.+?)`"
	"$x"^^pretdsl-dt:Release .
@pattern
	"p`(?<x>.+?)`"
	"$x"^^pretdsl-dt:Package .
@pattern
	"m`(?<x>.+?)`"
	"$x"^^pretdsl-dt:Module .
@pattern
	"f`(?<x>.+?)`"
	"$x"^^pretdsl-dt:File .
@pattern
	"cpan:(?<x>\\w+)"
	"$x"^^pretdsl-dt:CpanId .
@pattern
	"RT#(?<x>\\d+)"
	"$x"^^pretdsl-dt:RtBug .

# Generally useful predicates
@term label    rdfs:label .
@term comment  rdfs:comment .
@term seealso  rdfs:seeAlso .

# Makefile predicates
@term abstract_from          cpant:abstract_from .
@term author_from            cpant:author_from .
@term license_from           cpant:license_from .
@term requires_from          cpant:requires_from .
@term perl_version_from      cpant:perl_version_from .
@term version_from           cpant:version_from .
@term readme_from            cpant:readme_from .
@term no_index               cpant:no_index .
@term install_script         cpant:install_script .
@term requires               cpant:requires .
@term requires_external_bin  cpant:requires_external_bin .
@term recommends             cpant:recommends .
@term test_requires          cpant:test_requires .
@term configure_requires     cpant:configure_requires .
@term build_requires         cpant:build_requires .
@term provides               cpant:provides .

# Changelog predicates
@term issued     dc:issued .
@term changeset  dcs:changeset .
@term item       dcs:item .
@term versus     dcs:versus .

# Changelog datatypes
@term Addition            pretdsl-dt:Addition .
@term Bugfix              pretdsl-dt:Bugfix .
@term Change              pretdsl-dt:Change .
@term Documentation       pretdsl-dt:Documentation .
@term Packaging           pretdsl-dt:Packaging .
@term Regresion           pretdsl-dt:Regression .
@term Removal             pretdsl-dt:Removal .
@term SecurityFix         pretdsl-dt:SecurityFix .
@term SecurityRegression  pretdsl-dt:SecurityRegression .
@term Update              pretdsl-dt:Update .

PRETDSL_PROFILE

our $CALLBACKS = {};

use Module::Runtime qw< module_notional_filename > ;
use RDF::Trine qw< statement iri blank literal >;
use RDF::NS::Trine;

my $curie = RDF::NS::Trine->new('20120521');

sub _CB_ (&$)
{
	my ($coderef, $uri) = @_;
	$uri = "http://ontologi.es/pretdsl#dt/$uri" unless $uri =~ /\W/;
	$CALLBACKS->{$uri} = $coderef;
}

_CB_
{
	my ($lit, $cb) = @_;
	my ($dist, $version, $author) = split /\s+/, $lit->literal_value;
	if ($dist =~ m{::}) {
		goto $CALLBACKS->{'http://ontologi.es/pretdsl#dt/Module'}
	}
	if ($dist =~ m{/}) {
		goto $CALLBACKS->{'http://ontologi.es/pretdsl#dt/File'}
	}
	if (length $version) {
		goto $CALLBACKS->{'http://ontologi.es/pretdsl#dt/Release'}
	}
	goto $CALLBACKS->{'http://ontologi.es/pretdsl#dt/Distribution'};
} 'PerlResourceIdentifier';

_CB_
{
	my ($lit, $cb) = @_;
	my $dist = $lit->literal_value;
	
	my $node = iri(sprintf(
		'http://purl.org/NET/cpan-uri/dist/%s/project',
		$dist,
	));
	
	my $metacpan = iri(sprintf(
		'https://metacpan.org/release/%s',
		$dist,
	));
	
	$cb->(statement($node, $curie->rdf_type, $curie->doap_Project));
	$cb->(statement($node, $curie->doap_name, literal($dist)));
	$cb->(statement($node, $curie->URI('doap:programming-language'), literal('Perl')));
	$cb->(statement($node, $curie->doap_homepage, $metacpan));
	$cb->(statement($node, $curie->URI('doap:download-page'), $metacpan));
	
	return $node;
} 'Distribution';

_CB_
{
	my ($lit, $cb) = @_;
	my ($dist, $version, $author) = split /\s+/, $lit->literal_value;
	(my $version_token = $version) =~ s/\./-/g;

	my $dist_node = iri(sprintf(
		'http://purl.org/NET/cpan-uri/dist/%s/project',
		$dist,
	));
	
	my $node = iri(sprintf(
		'http://purl.org/NET/cpan-uri/dist/%s/v_%s',
		$dist,
		$version_token,
	));
	
	$cb->(statement($dist_node, $curie->doap_release, $node));
	$cb->(statement($node, $curie->rdf_type, $curie->doap_Version));
	$cb->(statement($node, $curie->doap_revision, literal($version, undef, $curie->xsd_string->uri)));
	$cb->(statement($node, $curie->dcterms_identifier, literal("$dist-$version", undef, $curie->xsd_string->uri)));

	$cb->(statement($node, $curie->rdf_type, iri('http://purl.org/NET/cpan-uri/terms#DeveloperRelease')))
		if $version =~ m{dev|_}i;

	if ($author =~ /^cpan:(\w+)$/)
	{
		$author = $1;
		my $author_node = iri(sprintf(
			'http://purl.org/NET/cpan-uri/person/%s',
			lc $author,
		));
		$cb->(statement($node, iri('http://ontologi.es/doap-changeset#released-by'), $author_node));
		$cb->(statement($dist_node, $curie->dcterms_contributor, $author_node));
		my $download = iri(sprintf(
			'http://backpan.cpan.org/authors/id/%s/%s/%s/%s-%s.tar.gz',
			substr(uc $author, 0, 1),
			substr(uc $author, 0, 2),
			uc($author),
			$dist,
			$version,
		));
		$cb->(statement($node, $curie->URI('doap:file-release'), $download));
	}
	
	return $node;
} 'Release';

_CB_
{
	my ($lit, $cb) = @_;
	my ($filename, $dist, $ver, $author) = split /\s+/, $lit->literal_value;
	$filename =~ s{^[.]/}{};
	
	my ($author_cpan) = ($author =~ m{^cpan:(\w+)$}i);
	
	my $node;
	if ($filename and $dist and $ver and $author_cpan)
	{
		$node = iri(sprintf 'http://api.metacpan.org/source/%s/%s-%s/%s', $author_cpan, $dist, $ver, $filename);

		my $release_download = iri(sprintf(
			'http://backpan.cpan.org/authors/id/%s/%s/%s/%s-%s.tar.gz',
			substr(uc $author_cpan, 0, 1),
			substr(uc $author_cpan, 0, 2),
			uc($author_cpan),
			$dist,
			$ver,
		));
		
		$cb->(statement($node, $curie->nfo_belongsToContainer, $release_download));
	}
	else
	{
		$node = blank();
	}

	$cb->(statement($node, $curie->rdf_type, $curie->nfo_FileDataObject));
	$cb->(statement($node, $curie->nfo_fileName, literal($filename)));

	if ($filename =~ /\.(PL|pl|pm|t|xs|c)$/)
		{ $cb->(statement($node, $curie->rdf_type, $curie->nfo_SourceCode)) }

	if ($filename =~ /\.(PL|pl|pm)$/)
		{ $cb->(statement($node, $curie->nfo_programmingLanguage, literal('Perl'))) }

	if ($filename =~ /\.(html)$/)
		{ $cb->(statement($node, $curie->rdf_type, $curie->nfo_HtmlDocument)) }
		
	if ($filename =~ /\.(pod)$/)
		{ $cb->(statement($node, $curie->rdf_type, $curie->nfo_Document)) }

	if ($filename =~ /^(Changes|README|TODO|LICENSE|INSTALL|NEWS|FAQ|.*\.txt)$/)
		{ $cb->(statement($node, $curie->rdf_type, $curie->nfo_TextDocument)) }

	return $node;
} 'File';

_CB_
{
	my ($lit, $cb) = @_;
	my ($filename, $dist, $ver, $author) = split /\s+/, $lit->literal_value;
	$filename =~ s{^::}{};
	my $joined = join q( ), grep defined,
		sprintf('lib/%s', module_notional_filename($filename)),
		$dist,
		$ver,
		$author,
		;
	my $r = $CALLBACKS->{'http://ontologi.es/pretdsl#dt/File'}->(literal($joined), $cb);
	$cb->(statement($r, $curie->rdfs_label, literal($filename)));
	return $r;
} 'Module';

_CB_
{
	my ($lit, $cb) = @_;
	my ($mod, $ver) = split /\s+/, $lit->literal_value;
	$mod =~ s{^::}{};
	
	if (length $ver)
	{
		return literal("$mod $ver", undef, "http://purl.org/NET/cpan-uri/terms#dsWithVersion");
	}
	
	return literal("$mod", undef, "http://purl.org/NET/cpan-uri/terms#dsWithoutVersion");
} 'Package';

_CB_
{
	my ($lit, $cb) = @_;
	my $node = iri(sprintf('http://purl.org/NET/cpan-uri/person/%s', lc $lit->literal_value));
	$cb->(statement($node, $curie->rdf_type, $curie->foaf_Person));
	$cb->(statement($node, $curie->foaf_nick, literal($lit->literal_value)));
	$cb->(statement($node, $curie->foaf_page, iri(sprintf 'https://metacpan.org/author/%s', uc $lit->literal_value)));
	return $node;
} 'CpanId';

_CB_
{
	my ($lit, $cb) = @_;
	my $node = iri(sprintf('http://purl.org/NET/cpan-uri/rt/ticket/%d', $lit->literal_value));
	$cb->(statement($node, $curie->rdf_type, iri('http://ontologi.es/doap-bugs#Issue')));
	$cb->(statement($node, iri('http://ontologi.es/doap-bugs#page'), iri(sprintf 'https://rt.cpan.org/Ticket/Display.html?id=%d', $lit->literal_value)));
	$cb->(statement($node, iri('http://ontologi.es/doap-bugs#id'), literal($lit->literal_value, undef, $curie->xsd_string->uri)));
	return $node;
} 'RtBug';

foreach my $change_type (qw(
	Addition Bugfix Change Documentation Packaging Regression
	Removal SecurityFix SecurityRegression Update
))
{
	_CB_
	{
		my ($lit, $cb) = @_;
		my $node = blank();
		$cb->(statement($node, $curie->rdf_type, iri("http://ontologi.es/doap-changeset#$change_type")));
		$cb->(statement($node, $curie->rdfs_label, literal($lit->literal_value)));
		return $node;		
	} $change_type;
}

use namespace::clean;
use base 'RDF::Trine::Parser::ShorthandRDF';

sub new
{
	my ($class, %args) = @_;
	$class->SUPER::new(
		datatype_callback => $CALLBACKS,
		profile           => $PROFILE,
		%args,
	);
}

__PACKAGE__
