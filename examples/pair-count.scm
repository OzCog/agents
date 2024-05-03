;
; pair-count.scm -- Example demo of assembling a word-pair counter.
;
; The generic goal is to be able to observe the external world, and to
; then count things that "happen at the same time". The demo here counts
; word pairs, observed to occur in sentences obtained from a text file.
;
; The demo builds up a processing pipeline, step by step, verifying that
; everythig works at each stage. The result is a carefully-crafted
; counting pipeline. An eventual goal of the sensory project is to
; auto-generate these kinds of pipelines. This demo is meant to
; illustrate a non-trivial pipeline.
;
; The steps proceed as follows:
; 1) Example of using the Link Grammar parser to generate word-pairs.
; 2) A debug printing utility.
; 3) Using filters to extract subelements of a data stream.
; 4) Using filters to increment counts on elements of a data stream.
; 5) Reading text from a file.
;
(use-modules (opencog) (opencog exec) (opencog persist))
(use-modules (opencog nlp) (opencog nlp lg-parse))
(use-modules (opencog sensory))
(use-modules (srfi srfi-1))

; --------------------------------------------------------------
; The Link Grammar "any" dictionary will parse a text string using
; a uniformly-dsitributed random planar graph. That is, it will
; generate random word-pair links, arranged so that no edges intersect.
; Lets try it.

(cog-execute!
	(LgParseBonds (Phrase "this is a test") (LgDict "any") (Number 1)))

; The `(Number 1)` says that only one parse is wanted.
;
; The result of parsing is a list of pairs. First item in a pair is
; the list of words in the sentence; the second is a list of the edges.
; Thus, each pair has the form
;     (LinkValue
;         (LinkValue (Word "this") (Word "is") (Word "a") (Word "test"))
;         (LinkValue (Edge ...) (Edge ...) ...))
;
; This pair should be thought of as a graph G = (V,E) where V is the
; set of vertices in the graph (here, the words) and E is the set of
; edges (here, these are word-pairs).
;
; One graph G is generated for each distinct parse. To avoid flooding
; the screen, only pne parse is asked for; thus, `(Number 1)`.

; View the contents of the AtomSpace:
(cog-report-counts)

; View the list of words in the AtomSpace:
(cog-get-atoms 'WordNode)

; Remove the words and edges:
(for-each cog-extract-recursive! (cog-get-atoms 'WordNode))

; Equivalently:
(extract-type 'WordNode)

; The only reason to remove is to start with a clean slate, as the demo
; progresses. Otherwise, it's OK to let things stay as they are.
; Assorted cruft will build up in the AtomSpace as the demo progresses,
; that cruft might be confusing.

; --------------------------------------------------------------
; Some philosophy:
; The filters and pipelines in the rest of this demo would be easy to
; create, if one was writing in pure scheme. Or, heck, even Python:
; there are Python wrappers into the AtomSpace.  But that's not the
; point.  The goal here is to do it in Atomese, so that the processing
; pipeline is stored in the AtomSpace, as Atomese, where other agents
; can examine it, work with it, modify it, hook it up, etc.
;
; For these demos, all of this hooking-up is purely manual. The sensory
; project (in https://github.com/opencog/sensory) aims to automate all
; of that; it's not quite ready and is still under construction.
;
; For debugging the demos here, we need a printer that can be called
; from Atomese. So here's how to call back into scheme from Atomese.
; This works for python, too.

; Call some arbitrary scheme function, and pass two arguments:
(define exo
	(ExecutionOutput
		(GroundedSchema "scm: foo")               ; the function
		(List (Concept "bar") (Concept "baz"))))  ; the arguments

(define (foo x y)
	(format #t "I got ~A and ~A\n" x y)
	(Concept "this is the foo reply"))

; Run it and see.
(cog-execute! exo)

; Now, define the utility printer we actually need.
; Use `x` as the return value, so that the printer is just a pass-thru.
(define (print-atom x) (format #t "Got ~A" x) x)

(define (debug-prt x)
	(ExecutionOutput (GroundedSchema "scm: print-atom") x))

; --------------------------------------------------------------
; Create a filter that will extract just the edges from the compound
; stream generated by the parser. The end-goal of this filter is to
; ignore the list of words, and will iterate over the list of edges.
;
; Build this up in a sequence of stages. First, a demo of the FilterLink
; combined with the RuleLink. The FilterLink is analogous to the srfi-1
; filter: it takes a pattern P and a list L and discards everything in
; the list that does not match the pattern P.
;
; The FilterLink allows an optional variable list, so that P(x,y,z)
; specifies a pattern P with variable portions x,y,z. If the input
; matches the pattern P(x,y,z), then the output of the filter is (x,y,z).
; That is, the filter acts as an extractor of pieces-parts. It is a
; disassembler of the input stream.
;
; See https://wiki.opencog.org/w/FilterLink
;
; The RuleLink specifies a rewrite rule P->Q. Given some input pattern P,
; it picks apart the contents of P and generates Q as output. That is,
; it specifies a mapping function from things that look like P to things
; Q made out of the parts of P. It is called a rule, because it is used
; in other places to implement logical implication.
;
; The RuleLink has an optional variable declaration, so that the rules
; can be understood as P(x,y,z)->Q(x,y,z) where the components x,y,z
; are picked out of the pattern P and are then used to build Q.
;
; See https://wiki.opencog.org/w/RuleLink
;
; The combination of Filter+Rule is analogous to the srfi-1 filter-map,
; so that the rewrite P->Q is applied to all the elements in the list L.
;
; The main difficulty in using all this is a need to unwrap all the
; stuff coming out of the parser, to get at exactly the part that we
; want.

; Step one: (Glob "$x") matches everything. So, the first demo is
; a no-op, except that it maps the entire result with one more LinkValue
; (because Globs do that, to list everythig that was globbed together.)

(define demo-filter
	(Filter
		(Variable "$x")
		(LgParseBonds (Phrase "this is a test") (LgDict "any") (Number 1))))

; Run it.
(cog-execute! demo-filter)

; Same as above, but with a no-op rule
(define demo-filter
	(Filter
		(Rule
			(Variable "$x") ; Input
			(Variable "$x")) ; Output
		(LgParseBonds (Phrase "this is a test") (LgDict "any") (Number 1))))

; Run it.
(cog-execute! demo-filter)

; Same as above, but now start matching stuff inside the stream.
; Each item in the stream is a pair: a list of words, followed
; by a list of edges. Match these two, and keep the words.
(define demo-filter
	(Filter
		(Rule
			; Match clause - one per parse.
			(LinkSignature
				(Type 'LinkValue)
				(Variable "$words")
				(Variable "$edges"))

			; Output
			(Variable "$words"))

		(LgParseBonds (Phrase "this is a test") (LgDict "any") (Number 1))))

; Run it.
(cog-execute! demo-filter)

; Same as above, but this time, ignore the words, and get the edges.
; Write it as a pipeline component, with two arguments: a parse source
; PASRC, so we don't have to keep working with the same sentence over
; and over, and a function FUNKY that will be applied to the edge-list.
; This function is meant to be a handy place to wire in more processing,
;
; Note that the result of parsing appears to be double-wrapped in
; LinkValue. The reason becomes more apparent if one asks for more
; than just one parse: the outer LinkValue groups all of the parses,
; while the inner one groups the edges in one parse. Thus, the
; function FUNKY will be called once per parse, and its argument
; will be the list of words in that parse.
(define (edge-filter PASRC FUNKY)
	(Filter
		(Rule
			; Match clause - one per parse.
			(LinkSignature
				(Type 'LinkValue)
				(Variable "$words")
				(Variable "$edge-list"))

			; Apply the function FUNKY to the edge-list
			(FUNKY (Variable "$edge-list")))
		PASRC))

(define parse-stuff
	(LgParseBonds (Phrase "this is a test") (LgDict "any") (Number 1)))

; Try it! Use the debug printer as the function to call.
(cog-execute! (edge-filter parse-stuff debug-prt))

; --------------------------------------------------------------
; The above showed how to pull out the edges from the parse stream.
; The next goal is to increment the count on the edges, whenever they
; are witnessed.

; A handy-dandy counter utility.
(define (incr-cnt edge)
	(SetValue edge (Predicate "count")
		(Plus (Number 0 0 1)
			(FloatValueOf edge (Predicate "count")
				; The all-zeros provides an initial value, if not set.
				(FloatValueOf (Number 0 0 0))))))

; Try it:
(cog-execute! (incr-cnt (Concept "foobar")))

; The count is stored at the key (Predicate "count").
; It can be viewed directly with scheme:
(cog-value (Concept "foobar") (Predicate "count"))

; ... or, equivalently, in Atomese:
(cog-execute! (ValueOf (Concept "foobar") (Predicate "count")))

; Use the previous utility function to wire the counter into
; the parsing pipeline. Note that the Rule is a bit fancier, here.
; It includes a type declaration to avoid counting if passed bad
; data: it insists that each individual edge really is of type 'Edge.
(define (edge-counter EDGE-LIST)
	(Filter
		(Rule
			(TypedVariable (Variable "$edge") (Type 'Edge))
			(Variable "$edge")
			(incr-cnt (Variable "$edge")))
		EDGE-LIST))

; Run it. Watch the counts increment
(cog-execute! (edge-filter parse-stuff edge-counter))

; --------------------------------------------------------------
; --------------------------------------------------------------
; To complete the pipeline, text is to be streamed from a text file.
; The `file-read.scm` demo in the sensory project already shows the
; this step. See
;
; https://github.com/opencog/sensory/raw/master/examples/file-read.scm
;
; The last part of that demo is repeated here.

; Opening the text stream will create a ValueStream. It needs to be
; placed where the parser can find it. Anywhere will do, as long as the
; parser attaches to it at the same place. Also: a demo text file must
; be present at /tmp/demo.txt for this to work.
(cog-execute!
	(SetValue (Anchor "pipe demo") (Predicate "text src")
		(Open (Type 'TextFileStream)
			(Sensory "file:///tmp/demo.txt"))))

; Parsing proceeds as before, with the text string replaced by the
; text stream. In the current design, the parser does not expose a
; stream, and so cog-execute! must be called once per line of text.
; This may change. Streams probably really should stream.
(define parse-stream
	(LgParseBonds
		(ValueOf (Anchor "pipe demo") (Predicate "text src"))
		(LgDict "any") (Number 1)))

(cog-execute! parse-stream)

; That's it. Now wire it all together:
(cog-execute! (edge-filter parse-stream edge-counter))

; Note the actual flow is different from the how this is written, above.
; First, the parse stream flows to the edge-filter, and then the
; edge-counter runs. Some twiddling about in scheme could straighten
; this out into a "natural" direction, but there does not seem to be
; much point to re-engineering this.

; --------------------------------------------------------------
