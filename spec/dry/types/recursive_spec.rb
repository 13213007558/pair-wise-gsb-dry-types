# frozen_string_literal: true

RSpec.describe Dry::Types::Recursive do
  subject(:tree) do
    Dry::Types::Recursive(%i[person company]) do |person, company|
      {
        person: Dry::Types["hash"].schema(
          name: Dry::Types["coercible.string"],
          employer: company
        ),
        company: Dry::Types["hash"].schema(
          name: Dry::Types["coercible.string"],
          employees: Dry::Types["nominal.array"].of(person)
        )
      }
    end
  end

  let(:compiler) { Dry::Types::Compiler.new(Dry::Types) }

  it "compiles schema, array, and sum nodes through the recursive AST" do
    integer = Dry::Types["strict.integer"]
    person = [:schema, [[
      [:key, [:kind, false, integer.to_ast]],
      [:key, [:company, false, [:reference, [:company, {}]]]]
    ], {}, {}]]
    company = [:schema, [[
      [:key, [:people, true, [:array, [[:reference, [:person, {}]], {}]]]]
    ], {}, {}]]
    nodes = [:sum, [integer.to_ast, [:reference, [:node, {}]], {}]]
    expect {
      compiler.([:recursive, [{person: person, company: company}, :person, :reject, {}]])
    }.not_to raise_error

    expect {
      compiler.([:recursion, [
        :node,
        [:array, [nodes, {}]],
        :reject,
        {}
      ]])
    }.not_to raise_error
  end

  it "preserves shared subgraphs while keying cached results by the concrete type" do
    company_input = {
      name: :Acme,
      employees: []
    }
    person_input = {name: :Jane, employer: company_input}
    company_input[:employees] << person_input

    result = tree.preserve_cycles.call(person_input)
    employer = result.fetch(:employer)
    employee = employer.fetch(:employees).first

    expect(result.fetch(:name)).to eql("Jane")
    expect(employer.fetch(:name)).to eql("Acme")
    expect(employee).to be(result)
    expect(employee.fetch(:employer)).to be(employer)
  end

  it "rejects real cycles by default" do
    person_input = {name: :Jane, employer: {}}
    company_input = {name: :Acme, employees: [person_input]}
    person_input[:employer] = company_input

    expect { tree.call(person_input) }.to raise_error(
      Dry::Types::RecursiveValueError,
      /contains a recursive cycle/
    )
  end

  it "preserves real cycles when requested" do
    person_input = {name: :Jane, employer: {}}
    company_input = {name: :Acme, employees: [person_input]}
    person_input[:employer].merge!(company_input)

    result = tree.preserve_cycles.call(person_input)

    expect(result.fetch(:employer).fetch(:employees).first).to be(result)
  end

  it "round-trips mutually recursive records through AST" do
    compiled = compiler.(tree.to_ast)
    input = {
      name: :Jane,
      employer: {name: :Acme, employees: []}
    }
    input[:employer][:employees] << input

    expect { compiled.call(input) }.to raise_error(Dry::Types::RecursiveValueError)
    preserved = compiled.preserve_cycles
    result = preserved.call(input)
    expect(result.dig(:employer, :employees, 0)).to be(result)
  end

  it "supports recursive arrays rooted directly at an array type" do
    integer = Dry::Types["strict.integer"]
    ast = [:recursive, [
      :node,
      [:array, [[:sum, [integer.to_ast, [:reference, [:node, {}]], {}]], {}]],
      :preserve,
      {}
    ]]
    type = compiler.(ast)
    input = [1, []]
    input[1][0] = input

    result = type.call(input)

    expect(result.first).to be(1)
    expect(result[1][0]).to be(result)
  end

  it "shares a non-cyclic object reached through nested references" do
    nested_tree = Dry::Types.recursive(%i[person company]) do |person, company|
      {
        person: Dry::Types["hash"].schema(
          name: Dry::Types["coercible.string"],
          "employer?": company,
          "friends?": Dry::Types["nominal.array"].of(person)
        ),
        company: Dry::Types["hash"].schema(
          name: Dry::Types["coercible.string"],
          "employees?": Dry::Types["nominal.array"].of(person)
        )
      }
    end

    company = {name: :Acme}
    jane = {name: :Jane, employer: company}
    joe = {name: :Joe, employer: company}
    root = {name: :Root, friends: [jane, joe]}

    result = nested_tree.call(root)
    people = result.fetch(:friends)

    expect(people[0].dig(:employer)).to be(people[1].dig(:employer))
  end

  it "reuses one input by output type rather than by input alone" do
    string_person = Dry::Types["hash"].schema("name?": Dry::Types["coercible.string"])
    integer_person = Dry::Types["hash"].schema("name?": Dry::Types["coercible.integer"])
    tagged = Dry::Types::Recursive(%i[string_person integer_person]) do |string_ref, integer_ref|
      {
        string_person: string_person.schema("integer_link?": integer_ref, "string_link?": string_ref),
        integer_person: integer_person.schema(
          "integer_link?": integer_ref,
          "string_link?": string_ref
        )
      }
    end

    shared = {name: "42"}
    shared_holder = {integer_link: shared, string_link: shared}
    input = {name: "7", integer_link: shared_holder, string_link: shared_holder}
    result = tagged.call(input)

    expect(result.fetch(:name)).to eql("7")
    integer_link = result.fetch(:integer_link)
    string_link = result.fetch(:string_link)
    expect(integer_link.fetch(:integer_link).fetch(:name)).to eql(42)
    expect(string_link.fetch(:string_link).fetch(:name)).to eql("42")
    expect(integer_link).not_to equal(string_link)
  end
end
