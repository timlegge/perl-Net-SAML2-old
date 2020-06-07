package Net::SAML2::Protocol::AuthnRequest;
use Moose;
use MooseX::Types::Moose qw /Str Int/;
use MooseX::Types::URI qw/ Uri /;
use MooseX::Types::Common::String qw/ NonEmptySimpleStr /;
use XML::Writer;

with 'Net::SAML2::Role::ProtocolMessage';

=head1 NAME

Net::SAML2::Protocol::AuthnRequest - SAML2 AuthnRequest object

=head1 SYNOPSIS

  my $authnreq = Net::SAML2::Protocol::AuthnRequest->new(
    id            => 'NETSAML2_Crypt::OpenSSL::Random::random_pseudo_bytes(16),
    issuer        => $self->{id},	# Service Provider (SP) Entity ID
    destination   => $destination,	# Identity Provider (IdP) SSO URL
    provider_name => $provider_name,	# Service Provider (SP) Human Readable Name
    issue_instant => DateTime->now,	# Defaults to Current Time
  );

  my $request_id = $authnreq->id;	# Store and Compare to InResponseTo

  or

  my $request_id = 'NETSAML2_' . unpack 'H*', Crypt::OpenSSL::Random::random_pseudo_bytes(16);

  my $authnreq = Net::SAML2::Protocol::AuthnRequest->as_xml(
    id            => $request_id,	# Unique Request ID will be returned in response
    issuer        => $self->{id},	# Service Provider (SP) Entity ID
    destination   => $destination,	# Identity Provider (IdP) SSO URL
    provider_name => $provider_name,	# Service Provider (SP) Human Readable Name
    issue_instant => DateTime->now,	# Defaults to Current Time
  );

=head1 METHODS

=cut

=head2 new( ... )

Constructor. Creates an instance of the AuthnRequest object.

Important Note: Best practice is to always do this first.  While it is possible
to call as_xml() first you do not have to set the id as it will be set for you
automatically.

However tracking the id is important for security to ensure that the response
has the same id in the InResponseTo attribute.

Arguments:

=over

=item B<nameidpolicy_format>

Format attribute for NameIDPolicy

=item B<AuthnContextClassRef>, B<AuthnContextDeclRef>

Each one is an arrayref containing values for AuthnContextClassRef and AuthnContextDeclRef.
If any is populated, the RequestedAuthnContext will be included in the request.

=item B<RequestedAuthnContext_Comparison>

Value for the I<Comparison> attribute in case I<RequestedAuthnContext> is included
(see above). Default value is I<exact>.

=back

=cut

has 'nameid' => (isa => NonEmptySimpleStr, is => 'rw', required => 0);

has 'nameidpolicy_format' => (isa => Str, is => 'rw', required => 0);

has 'nameid_allow_create' => (
    isa       => 'Bool',
    is        => 'rw',
    required  => 0,
    predicate => 'has_nameid_allow_create'
);

has 'assertion_url' => (isa => Uri, is => 'rw', required => 0, coerce => 1);
has 'assertion_index' => (isa => Int, is => 'rw', required => 0);
has 'attribute_index' => (isa => Int, is => 'rw', required => 0);
has 'protocol_binding' => (isa => Uri, is => 'rw', required => 0, coerce => 1);
has 'provider_name' => (isa => Str, is => 'rw', required => 0);

# RequestedAuthnContext:
has 'AuthnContextClassRef' => (isa => 'ArrayRef[Str]', is => 'rw', required => 0, default => sub {[]});
has 'AuthnContextDeclRef' => (isa => 'ArrayRef[Str]', is => 'rw', required => 0, default => sub {[]});
has 'RequestedAuthnContext_Comparison' => (isa => Str, is => 'rw', required => 0, default => 'exact');

around BUILDARGS => sub {
    my $orig = shift;
    my $self = shift;

    my %params = @_;
    if ($params{nameid_format}) {
        unless (defined $params{nameidpolicy_format}) {
            $params{nameidpolicy_format} = $params{nameid_format};
        }
    }

    return $self->$orig(%params);
};

=head2 as_xml( )

Returns the AuthnRequest as XML.

=cut

sub as_xml {
    my ($self) = @_;
    my $saml = 'urn:oasis:names:tc:SAML:2.0:assertion';
    my $samlp = 'urn:oasis:names:tc:SAML:2.0:protocol';
    my $x = XML::Writer->new(
        OUTPUT => 'self',
        NAMESPACES => 1,
        FORCED_NS_DECLS => [$saml, $samlp],
        PREFIX_MAP => {
            $saml => 'saml2',
            $samlp => 'saml2p'
        }
    );

   my $req_atts = {
            ID => $self->id,
            IssueInstant => $self->issue_instant,
            Version => '2.0',
        };

        my $issuer_attrs = {};

        my $protocol_bindings = {
            'HTTP-POST' => 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST'
        };

        my $att_map = {
            'assertion_url' => 'AssertionConsumerServiceURL',
            'assertion_index' => 'AssertionConsumerServiceIndex',
            'attribute_index' => 'AttributeConsumingServiceIndex',
            'protocol_binding' => 'ProtocolBinding',
            'provider_name' => 'ProviderName',
            'destination' => 'Destination',
            'issuer_namequalifier' => 'NameQualifier',
            'issuer_format' => 'Format',
        };

        foreach my $opt ( qw(assertion_url assertion_index protocol_binding
            attribute_index provider_name destination
            issuer_namequalifier issuer_format) ) {
            if (defined (my $val = $self->$opt())) {
                if ( $opt eq 'protocol_binding' ) {
                    $req_atts->{ $att_map->{$opt} } = $protocol_bindings->{$val};
                } elsif ($opt eq 'issuer_namequalifier' || $opt eq 'issuer_format') {
                    $issuer_attrs->{ $att_map->{$opt} } = $val;
                } else {
                    $req_atts->{ $att_map->{$opt} } = $val;
                }
            }
        }

    $x->startTag([$samlp, 'AuthnRequest'], %$req_atts);
    $x->dataElement([$saml, 'Issuer'], $self->issuer, %$issuer_attrs);
    if ($self->nameid) {
        $x->startTag([$saml, 'Subject']);
        $x->dataElement([$saml, 'NameID'], undef, NameQualifier => $self->nameid);
        $x->endTag(); # Subject
    }
    if ($self->nameidpolicy_format) {
        $x->dataElement([$samlp, 'NameIDPolicy'],
            undef,
            Format => $self->nameidpolicy_format,
            $self->has_nameid_allow_create
                ? (AllowCreate => $self->nameid_allow_create)
                : (),
        );
    }
    if (@{$self->AuthnContextClassRef} || @{$self->AuthnContextDeclRef}) {
        $x->startTag([$samlp, 'RequestedAuthnContext'], Comparison => $self->RequestedAuthnContext_Comparison);
        foreach my $ref (@{$self->AuthnContextClassRef}) {
            $x->dataElement([$saml, 'AuthnContextClassRef'], $ref);
        }
        foreach my $ref (@{$self->AuthnContextDeclRef}) {
            $x->dataElement([$saml, 'AuthnContextDeclRef'], $ref);
        }
        $x->endTag(); # RequestedAuthnContext
    }
    $x->endTag(); #AuthnRequest
    $x->end();
}

__PACKAGE__->meta->make_immutable;
