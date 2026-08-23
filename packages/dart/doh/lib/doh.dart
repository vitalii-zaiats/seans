/// Resolves names over HTTPS instead of asking the network's own resolver.
///
/// Not a way past a blocked site — a name that resolves is not a site that
/// answers — but it takes the part somebody else controls out of the question.
/// Performing the request is the caller's job, through the [DohFetcher] a
/// [DohResolver] is built with.
library;

export 'src/resolver.dart';
