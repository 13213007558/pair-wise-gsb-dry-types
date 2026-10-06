# frozen_string_literal: true

RSpec.describe Dry::Types::Recursive do
  subject(:feed) do
    Dry::Types.Recursive(:item, definitions: definitions)
  end

  let(:hash) { Dry::Types["nominal.hash"] }
  let(:array) { Dry::Types["nominal.array"] }
  let(:string) { Dry::Types["strict.string"] }
  let(:integer) { Dry::Types["strict.integer"] }

  let(:definitions) do
    author_ref = Dry::Types.recursive_ref(:author)
    post_ref = Dry::Types.recursive_ref(:item)

    author = hash.schema(
      kind: Dry::Types["strict.string"].constrained(eql: "author"),
      name: string,
      posts: array.of(post_ref)
    )

    post = hash.schema(
      kind: Dry::Types["strict.string"].constrained(eql: "post"),
      title: string,
      author: author_ref,
      related: array.of(post_ref)
    )

    {author: author, item: author | post | integer.optional}
  end

  it "coerces mutually recursive schemas through arrays and sums" do
    result = feed.(
      kind: "author",
      name: "Jane",
      posts: [
        {
          kind: "post",
          title: "Hello",
          author: {kind: "author", name: "Jane", posts: []},
          related: []
        }
      ]
    )

    expect(result).to eql(
      kind: "author",
      name: "Jane",
      posts: [
        {
          kind: "post",
          title: "Hello",
          author: {kind: "author", name: "Jane", posts: []},
          related: []
        }
      ]
    )
  end

  it "supports zero-argument recursive blocks and late reference aliases" do
    type = Dry::Types.recursive(:tree) do
      Dry::Types["nominal.hash"].schema(
        value: "strict.integer",
        children: Dry::Types["nominal.array"].of(tree)
      )
    end

    expect(type.(value: 1, children: [{value: 2, children: []}])).to eql(
      value: 1,
      children: [{value: 2, children: []}]
    )
  end

  it "preserves shared, acyclic objects after coercion" do
    author_input = {kind: "author", name: "Jane", posts: []}
    first_post = {kind: "post", title: "One", author: author_input, related: []}
    second_post = {kind: "post", title: "Two", author: author_input, related: []}
    root_input = [first_post, second_post]

    result = Dry::Types.Recursive(:posts, array.of(feed.type)).(root_input)

    expect(result[0][:author]).to equal(result[1][:author])
  end

  it "keeps caches separate for different named types" do
    person_ref = Dry::Types.recursive_ref(:person)
    employee_ref = Dry::Types.recursive_ref(:employee)

    person = hash.schema(
      name: string,
      friend: Dry::Types["nil"] | person_ref
    )
    employee = hash.schema(
      name: string,
      employee_id: integer,
      friend: Dry::Types["nil"] | employee_ref
    )

    person_type = Dry::Types.Recursive(:person, person)
    employee_type = Dry::Types.Recursive(:employee, employee)

    shared = {name: "John", friend: nil}

    person_result = person_type.(shared)
    employee_input = {name: "John", friend: nil}
    employee_result = employee_type.call_safe(employee_input) do
      :invalid
    end

    expect(person_result).to eql(name: "John", friend: nil)
    expect(employee_result).to be(:invalid)
  end

  it "rejects real cycles by default" do
    author = {kind: "author", name: "Jane", posts: []}
    post = {kind: "post", title: "Hello", author: author, related: []}
    author[:posts] = [post]
    post[:related] = [post]

    expect { feed.(author) }.to raise_error(
      Dry::Types::CircularReferenceError,
      /circular reference :author/
    )
    expect(feed.try(author)).to be_failure
  end

  it "supports lax handling for rejected and retained cycles" do
    author = {kind: "author", name: "Jane", posts: []}
    post = {kind: "post", title: "Hello", author: author, related: []}
    author[:posts] = [post]
    post[:related] = [post]

    expect(feed.lax.(author)).to equal(author)

    kept = Dry::Types.Recursive(:item, definitions: definitions, cycles: :keep)
    result = kept.lax.(author)

    expect(result[:posts][0][:author].object_id).to be(result.object_id)
  end

  context "with cycles kept" do
    subject(:feed) do
      Dry::Types.Recursive(:item, definitions: definitions, cycles: :keep)
    end

    it "rebuilds the graph and retains the cycle" do
    author = {kind: "author", name: "Jane", posts: []}
    post = {kind: "post", title: "Hello", author: author, related: []}
    author[:posts] = [post]
    post[:related] = [post]

    result = feed.(author)

      post_result = result[:posts][0]
      related_post_result = post_result[:related][0]

      expect(post_result[:author].object_id).to be(result.object_id)
      expect(related_post_result[:author].object_id).to be(result.object_id)
    end
  end

  it "round-trips through the compiler" do
    compiled = Dry::Types::Compiler.new(Dry::Types).(feed.to_ast)
    author = {kind: "author", name: "Jane", posts: []}
    post = {kind: "post", title: "Hello", author: author, related: []}
    author[:posts] = [post]
    post[:related] = [post]

    kept = Dry::Types.Recursive(:item, definitions: definitions, cycles: :keep)
    keep = Dry::Types::Compiler.new(Dry::Types).(kept.to_ast)

    expect(Dry::Types::Compiler.new(Dry::Types).(compiled.to_ast)).to be_a(described_class)

    result = keep.(author)

    expect(compiled).to be_a(described_class)
    expect(result[:posts][0][:author].object_id).to be(result.object_id)
  end

  it "has a finite inspection and round-trips AST metadata" do
    expect(feed.inspect).to include("Recursive<item")
    expect(feed.meta(tag: :graph).to_ast[1][3]).to eql(tag: :graph)
  end

  it "rejects a recursive reference outside of a recursive root" do
    reference = Dry::Types.recursive_ref(:missing)
    reference.bind(Dry::Types["nominal.any"])

    expect { reference.(nil) }.to raise_error(
      Dry::Types::RecursiveReferenceError,
      /not bound to a recursive root/
    )
  end
end
