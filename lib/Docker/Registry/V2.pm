package Docker::Registry::Request;
  use Moose;

  has headers => (is => 'ro', isa => 'HTTP::Headers', default => sub { HTTP::Headers->new });
  has method => (is => 'ro', isa => 'Str', required => 1);
  has url => (is => 'ro', isa => 'Str', required => 1);
  has content => (is => 'ro', isa => 'Maybe[Str]');

  sub header_hash {
    my $self = shift;
    my $headers = {};
    $self->headers->scan(sub { $headers->{ $_[0] } = $_[1] });
    return $headers;
  }

  sub header {
    my ($self, $header, $value) = @_;
    $self->headers->header($header, $value) if (defined $value);
    return $self->headers->header($header);
  }

package Docker::Registry::Response;
  use Moose;
  use HTTP::Headers;

  has content  => (is => 'ro', isa => 'Str');
  has status   => (is => 'ro', isa => 'Int', required => 1);
  has headers  => (is => 'rw', isa => 'HashRef', required => 1);

  sub header {
    my ($self, $header) = @_;
    return $self->headers->{ $header };
  }

package Docker::Registry::Exception;
  use Moose;
  extends 'Throwable::Error';

package Docker::Registry::Exception::HTTP;
  use Moose;
  extends 'Docker::Registry::Exception';
  has status => (is => 'ro', isa => 'Int', required => 1);

package Docker::Registry::Exception::Unauthorized;
  use Moose;
  extends 'Docker::Registry::Exception::HTTP';

package Docker::Registry::Call::Repositories;
  use Moose;
  has n => (is => 'ro', isa => 'Int');
  has limit => (is => 'ro', isa => 'Int');

package Docker::Registry::Result::Repositories;
  use Moose;
  has repositories => (is => 'ro', isa => 'ArrayRef[Str]');

package Docker::Registry::Call::RepositoryTags;
  use Moose;
  has repository => (is => 'ro', isa => 'Str', required => 1);
  has n => (is => 'ro', isa => 'Int');
  has limit => (is => 'ro', isa => 'Int');

package Docker::Registry::Result::RepositoryTags;
  use Moose;
  has name => (is => 'ro', isa => 'Str', required => 1);
  has tags => (is => 'ro', isa => 'ArrayRef[Str]', required => 1);

package Docker::Registry::V2;
  use Moose;

  has url => (is => 'ro', isa => 'Str', required => 1);
  has api_base => (is => 'ro', default => 'v2');

  has caller => (is => 'ro', does => 'Docker::Registry::IO', default => sub {
    require Docker::Registry::IO::Simple;
    Docker::Registry::IO::Simple->new;  
  });
  has auth => (is => 'ro', does => 'Docker::Registry::Auth', default => sub {
    require Docker::Registry::Auth::None;
    Docker::Registry::Auth::None->new; 
  });

  use JSON::MaybeXS qw//;
  has _json => (is => 'ro', default => sub {
    JSON::MaybeXS->new;
  });
  sub process_json_response {
    my ($self, $response) = @_;
    if ($response->status == 200) {
      my $struct = eval {
        $self->_json->decode($response->content);
      };
      if ($@) {
        Docker::Registry::Exception->throw({ message => $@ });
      }
      return $struct;
    } elsif ($response->status == 401) {
      Docker::Registry::Exception::Unauthorized->throw({
        message => $response->content,
        status  => $response->status,
      });
    } else {
      Docker::Registry::Exception::HTTP->throw({
        message => $response->content,
        status  => $response->status
      });
    }
  }

  sub repositories {
    my $self = shift;
    # Inputs n, last
    #
    # GET /v2/_catalog
    #
    # Header next
    # {
    #   "repositories": [
    #     <name>,
    #     ...
    #   ]
    # }
    my $call_class = 'Docker::Registry::Call::Repositories';
    my $call = $call_class->new({ @_ });
    my $params = { };
    $params->{ n } = $call->n if (defined $call->n);
    $params->{ limit } = $call->limit if (defined $call->limit);

    my $request = Docker::Registry::Request->new(
      parameters => $params,
      method => 'GET',
      url => (join '/', $self->url, $self->api_base, '_catalog')
    );
    $request = $self->auth->authorize($request);
    my $response = $self->caller->send_request($request);
    my $result_class = 'Docker::Registry::Result::Repositories';
    my $result = $result_class->new($self->process_json_response($response));
    return $result;
  }

  sub repository_tags {
    my $self = shift;

    # n, last
    #GET /v2/$repository/tags/list
    #
    #{"name":"$repository","tags":["2017.09","latest"]}
    my $call_class = 'Docker::Registry::Call::RepositoryTags';
    my $call = $call_class->new({ @_ });
    my $params = { };

    $params->{ n } = $call->n if (defined $call->n);
    $params->{ limit } = $call->limit if (defined $call->limit);

    my $request = Docker::Registry::Request->new(
      parameters => $params,
      method => 'GET',
      url => (join '/', $self->url, $self->api_base, $call->repository, 'tags/list')
    );
    $request = $self->auth->authorize($request);
    my $response = $self->caller->send_request($request);
    my $result_class = 'Docker::Registry::Result::RepositoryTags';
    my $result = $result_class->new($self->process_json_response($response));
    return $result;
  }

  sub is_registry {
    my $self = shift;
    # GET /v2
    # if (200 or 401) and (header.Docker-Distribution-API-Version eq 'registry/2.0')
  }

  # Actionable failure conditions, covered in detail in their relevant sections,
  # are reported as part of 4xx responses, in a json response body. One or more 
  # errors will be returned in the following format:
  # {
  #  "errors:" [{
  #          "code": <error identifier>,
  #          "message": <message describing condition>,
  #          "detail": <unstructured>
  #      },
  #      ...
  #  ]
  # }

  # ECR: returns 401 error body as "Not Authorized"
  sub process_error {
    
  }

  sub request {
    
  }
1;
