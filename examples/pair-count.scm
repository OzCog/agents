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
; Note how a bunch of Edges flew by; these specify the word pairs.
; Note how the list of edges is wrapped by a `LinkValue`.
; Note how a list of words is generated, before the edges; it is also
; wrapped in a LinkValue. The graph, as a whole, consisting of a list of
; vertexes (the words) and edges, is wrapped in a LinkValue.

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

; Now, define the utility printer we actually need:
(define (print-atom x) (format #t "Got ~A" x))

(define (debug-prt x)
	(ExecutionOutput
		(GroundedSchema "scm: print-atom")
		(List x)))

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
		(Glob "$x")
		(LgParseBonds (Phrase "this is a test") (LgDict "any") (Number 1))))

; Run it.
(cog-execute! demo-filter)

; Same as above, but with a no-op rule
(define demo-filter
	(Filter
		(Rule
			(Glob "$x") ; Input
			(Glob "$x")) ; Output
		(LgParseBonds (Phrase "this is a test") (LgDict "any") (Number 1))))

; Run it.
(cog-execute! demo-filter)

; Same as above, but now start matching stuff inside the stream.
; This is still an almost trivial no-op; but it does unwrap one
; layer of LinkValue.
(define demo-filter
	(Filter
		(Rule
			; Match clause - one per parse.
			(LinkSignature
				(Type 'LinkValue)
				(Glob "$stuff"))

			; Output
			(Glob "$stuff"))

		(LgParseBonds (Phrase "this is a test") (LgDict "any") (Number 1))))

; Run it.
(cog-execute! demo-filter)

;Pair
(define demo-filter
	(Filter
		(Rule
			; Match clause - one per parse.
			(LinkSignature
				(Type 'LinkValue)
				(Glob "$stuff"))

			; Output
			(debug-prt (Glob "$ftuff")))

		(LgParseBonds (Phrase "this is a test") (LgDict "any") (Number 1))))

; Run it.
(cog-execute! demo-filter)


(define edge-filter
	(Filter
		(Rule
			; Match clause - one per parse.
			(LinkSignature
				(Type 'LinkValue) ; type of (vertex,edge) pair
				(Type 'LinkValue) ; the word-list
				(LinkSignature    ; the edge-list
					(Type 'LinkValue)  ; edge-list wrapper
					(Glob "$edge-list")))      ; all of the edges
			; Pipeline to apply to the resulting match.
			(debug-prt (Glob "$edge-list"))
		)
		(LgParseBonds (Phrase "this is a test") (LgDict "any") (Number 1))))

(cog-execute! edge-filter)

; --------------------------------------------------------------
; This demo starts where the `file-read.scm` demo in the sensory
; project leaves off. See
; https://github.com/opencog/sensory/raw/master/examples/file-read.scm




; --------------------------------------------------------------
; Return a text parser that counts edges on a stream. The
; `txt-stream` must be an Atom that can serve as a source of text.
; Typically, `txt-stream` will be
;    (ValueOf (Concept "some atom") (Predicate "some key"))
; and the Value there will be a LinkStream from some file or
; other text source.
;
; These sets up a processing pipeline in Atomese, and returns that
; pipeline. The actual parsing all happens in C++ code, not in scheme
; code. The scheme here is just to glue the pipeline together.
(define (make-parser txt-stream)
	;
	; Pipeline steps, from inside to out:
	; * LGParseBonds tokenizes a sentence, and then parses it.
	; * The PureExecLink makes sure that the parsing is done in a
	;   sub-AtomSpace so that the main AtomSpace is not garbaged up.
	;
	; The result of parsing is a list of pairs. First item in a pair is
	; the list of words in the sentence; the second is a list of the edges.
	; Thus, each pair has the form
	;     (LinkValue
	;         (LinkValue (Word "this") (Word "is") (Word "a") (Word "test"))
	;         (LinkValue (Edge ...) (Edge ...) ...))
	;
	; The outer Filter matches this, so that (Glob "$edge-list") is
	; set to the LinkValue of Edges.
	;
	; The inner Filter loops over the list of edges, and invokes a small
	; pipe to increment the count on each edge.
	;
	; The counter is a non-atomic pipe of (SetValue (Plus 1 (GetValue)))
	;
	(define NUML (Number 4))
	(define DICT (LgDict "any"))

	; Increment the count on one edge.
	(define (incr-cnt edge)
		(SetValue edge (Predicate "count")
			(Plus (Number 0 0 1)
				(FloatValueOf edge (Predicate "count") (FloatValueOf (Number 0 0 0))))))

	; Given a list (an Atomese LinkValue list) of parse results,
	; extract the edges and increment the count on them.
	(define (count-edges parsed-stuff)
		(Filter
			(Rule
				; (Variable "$edge")
				(TypedVariable (Variable "$edge") (Type 'Edge))
				(Variable "$edge")
				(incr-cnt (Variable "$edge")))
			parsed-stuff))

	; Parse text in a private space.
	(define (parseli phrali)
		(PureExecLink (LgParseBonds phrali DICT NUML)))

	; Given an Atom `phrali` holding text to be parsed, get that text,
	; parse it, and increment the counts on the edges.
	(define (filty phrali)
		(Filter
			(Rule
				; Type decl
				(Glob "$x")
				; Match clause - one per parse.
				(LinkSignature
					(Type 'LinkValue) ; the wrapper for the pair
					(Type 'LinkValue) ; the word-list
					(LinkSignature    ; the edge-list
						(Type 'LinkValue)  ; edge-list wrapper
						(Glob "$edge-list")))      ; all of the edges
				; Pipeline to apply to the resulting match.
				(count-edges (Glob "$edge-list"))
			)
			(parseli phrali)))

	; Return the parser.
	(filty txt-stream)
)

; --------------------------------------------------------------
; Demo wrapper showing how to use the above: Parse a string.
; PLAIN-TEXT should be a scheme string.
;
; Verify this works as follows:
;    (obs-txt "this is a test")
;    (cog-report-counts)
; Note the abundance of WordNodes listed in the report.
;    (cog-get-atoms 'WordNode)
; Cleanup after use:
;    (for-each cog-extract-recursive! (cog-get-atoms 'WordNode))
;    (extract-type 'WordNode)
(define (obs-txt PLAIN-TEXT)

	; We don't need to create this over and over; once is enough.
	(define txt-stream (ValueOf (Concept "foo") (Predicate "some place")))
	(define parser (make-parser txt-stream))

	(define phrali (Phrase PLAIN-TEXT))
	(cog-set-value! (Concept "foo") (Predicate "some place") phrali)

	(cog-execute! parser)

	; Remove the phrase-link, return the list of edges.
	(cog-set-value! (Concept "foo") (Predicate "some place") #f)
	(cog-extract-recursive! phrali)
)

; --------------------------------------------------------------
; Demo wrapper: Parse contents of a file.
(define (obs-file FILE-NAME)

	; We don't need to create this over and over; once is enough.
	(define txt-stream (ValueOf (Concept "foo") (Predicate "some place")))
	(define parser (make-parser txt-stream))

	(define phrali (Open (Type 'TextFileStream)
		(Sensory (string-append "file://" FILE-NAME))))

	(cog-execute!
		(SetValue (Concept "foo") (Predicate "some place") phrali))

	; Parse only first line of file:
	; (cog-execute! parser)

	; Loop over all lines.
	(define (looper) (cog-execute! parser) (looper))

	; At end of file, exception will be thrown. Catch it.
	(catch #t looper
		(lambda (key . args) (format #t "The end ~A\n" key)))

	(cog-extract-recursive! phrali)
)

; --------------------------
; Issues.
; Parses arrive as LinkValues. We want to apply a function to each.
; How? Need:
; 4) IncrementLink just like cog-inc-value!
;    or is it enough to do atomic lock?
;    Make SetValue exec under lock. ... easier said than done.
;    risks deadlock.
;
; cog-update-value calls
; Ideally, call asp->increment_count(h, key, fvp->value()));

; Below works but is a non-atomic increment.
(define ed (Edge (Bond "ANY") (List (Word "words") (Word "know"))))
(define (doinc)
	(cog-execute!
		(SetValue ed (Predicate "count")
			(Plus (Number 0 0 1)
				(FloatValueOf ed (Predicate "count") (Number 0 0 0))))))

; Here's a demo of what file-access looks like.
(cog-execute!
   (SetValue (Concept "foo") (Predicate "some place")
      (FileRead "file:///tmp/demo.txt")))

; Wait ...
(define txt-stream-gen
	(ValueOf (Concept "foo") (Predicate "some place")))

; (cog-execute! (LgParseBonds txt-stream-gen DICT NUML))

; (load "count-agent.scm")
; (obs-txt "Some kind of sentence to process, hell yeah!")
; (obs-file "/tmp/demo.txt")
; (cog-report-counts)
; (cog-get-atoms 'WordNode)
