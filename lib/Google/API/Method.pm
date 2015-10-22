package Google::API::Method;

use strict;
use warnings;

use Encode;
use HTTP::Request;
use URI;
use URI::Escape qw/uri_escape/;

use Data::Dumper;

sub new {
    my $class = shift;
    my (%param) = @_;
    for my $required (qw/ua json_parser base_url opt doc/) {
        die unless $param{$required};
    }
    bless { %param }, $class;
}

sub execute {
    my ($self, $arg) = @_;
    my $url = $self->{base_url} . $self->{doc}{path};
    my $http_method = uc($self->{doc}{httpMethod});
    my %required_param;
    for my $p (@{$self->{doc}{parameterOrder}}) {
        $required_param{$p} = delete $self->{opt}{$p};
        if ($self->{opt}{body} && $self->{opt}{body}{$p}) {
            $required_param{$p} = delete $self->{opt}{body}{$p};
        }
    }
    # In the case of media upload for storage objects, a different path is provided
    if( $http_method eq 'POST' && $self->{doc}{id} eq "storage.objects.insert" ) {
        # This path is absolute, to strip out everything from the base other than the hostname
        $self->{base_url} =~ /^(https?:\/\/[^\/]+)/;
        my $root_url = $1;
        die "Unable to determine server name in execute()" if !$root_url;
        $url = $root_url . $self->{doc}{mediaUpload}{protocols}{simple}{path};
    }
    $url =~ s/{([^}]+)}/uri_escape(delete $required_param{$1})/eg;
    my $uri = URI->new($url);
    my $request;
    if ($http_method eq 'POST' ||
        $http_method eq 'PUT' ||
        $http_method eq 'PATCH' ||
        $http_method eq 'DELETE') {
        # Some API's (ie: admin/directoryv1/groups/delete) require requests 
        # with an empty body section to be explicitly zero length.
        if (my $media = $self->{opt}{media_body}) {
            my ($path, $upload_type);
            unless ($self->{opt}{body}) {
                $upload_type = 'media';
                #$path = $self->{doc}{mediaUpload}{protocols}{simple}{path};
            } else {
                # TODO implement multipart/related 
            }
            #$path =~ s/{([^}]+)}/uri_escape(delete $required_param{$1})/eg;
            $uri->query_form({
                %required_param,
                uploadType => $upload_type,
                name => $media->basename,
            });
            $request = HTTP::Request->new($http_method => $uri);
            $request->content_type($media->mime_type);
            $request->content_length($media->length);
            $request->content($media->bytes);
        } elsif (%{$self->{opt}{body}}) {
            $uri->query_form(\%required_param);
            $request = HTTP::Request->new($http_method => $uri);
            $request->content_type('application/json');
            $request->content($self->{json_parser}->encode($self->{opt}{body}));
        } else {
            $uri->query_form(\%required_param);
            $request = HTTP::Request->new($http_method => $uri);
            $request->content_length(0);
        }
    } elsif ($http_method eq 'GET') {
        my $body = $self->{opt}{body} || {};
        my %q = (
            %required_param,
            %$body,
        );
        if ($arg->{key}) {
            $q{key} = $arg->{key};
        }
        $uri->query_form(\%q);
        $request = HTTP::Request->new($http_method => $uri);
    }
    if ($arg->{auth_driver}) {
        $request->header('Authorization',
            sprintf "%s %s",
                $arg->{auth_driver}->token_type,
                $arg->{auth_driver}->access_token);
    }
    my $response = $self->{ua}->request($request);
    if ($response->code == 401 && $arg->{auth_driver}) {
        $arg->{auth_driver}->refresh;
        $request->header('Authorization',
            sprintf "%s %s",
                $arg->{auth_driver}->token_type,
                $arg->{auth_driver}->access_token);
        $response = $self->{ua}->request($request);
    }
    unless ($response->is_success) {
        $self->_die_with_error($response);
    }
    if ($response->code == 204) {
        return 1;
    }
    return $response->header('content-type') =~ m!^application/json!
           ? $self->{json_parser}->decode(decode_utf8($response->content))
           : $response->content
           ;
}

sub _die_with_error {
    my ($self, $response) = @_;
    my $err_str = $response->status_line;
    if ($response->content
        && $response->header('content-type') =~ m!^application/json!) {
        my $content = $self->{json_parser}->decode(decode_utf8($response->content));
        $err_str = "$err_str: $content->{error}{message}";
    }
    die $err_str;
}

1;
__END__

=encoding utf-8

=for stopwords

=head1 NAME

Google::API::Method - An implementation of methods part in Discovery Document Resource

=head1 SYNOPSIS

  use Google::API::Method;
  my $method = Google::API::Method->new({
      # options
      # see also Google::API::Client 
  });
  my $result = $method->execute;

=head1 DESCRIPTION

Google::API::Method is an implementation of methods part in Discovery Document Resource.

=head1 METHODS

=over 4

=item new

=item execute

=back

=head1 AUTHOR

Takatsugu Shigeta E<lt>shigeta@cpan.orgE<gt>

=head1 COPYRIGHT

Copyright 2011- Takatsugu Shigeta

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

=cut
