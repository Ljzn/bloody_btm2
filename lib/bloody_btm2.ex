defmodule BloodyBtm2 do
  alias BloodyBtm2.Serializer, as: Se

  @issuance_input_type <<0>>
  @spend_input_type <<1>>
  @veto_input_type <<2>>
  @coinbase_input_type <<3>>

  @original_output_type <<0>>

  def btm_asset_id,
    do: <<0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF::256>>

  def input_type(type) do
    case type do
      @issuance_input_type ->
        :issuance

      @spend_input_type ->
        :spend

      @veto_input_type ->
        :veto

      @coinbase_input_type ->
        :coinbase
    end
  end

  def output_type(type) do
    case type do
      @original_output_type ->
        :original_output
    end
  end

  # TODO simplify
  def encode_block(b) when is_map(b) do
    b.serflag <>
      Se.put_uvarint(b.version) <>
      Se.put_uvarint(b.height) <>
      b.prev_block <>
      Se.put_uvarint(b.timestamp) <>
      Se.put_ext_string(b.block_commitment) <>
      Se.put_ext_string(b.block_witness) <>
      Se.put_ext_string(b.sup_links) <>
      encode_list(b.txs, &encode_tx/1)
  end

  @doc """
  Decode a binary format raw block.
  """
  def decode_block(binary) when is_binary(binary) do
    <<serflag::binary-size(1), binary::binary>> = binary
    {version, binary} = Se.get_uvarint(binary)
    {height, binary} = Se.get_uvarint(binary)

    <<prev_block::binary-size(32), binary::binary>> = binary
    {timestamp, binary} = Se.get_uvarint(binary)

    {block_commitment, binary} = Se.get_ext_string(binary)
    {block_witness, binary} = Se.get_ext_string(binary)
    {sup_links, binary} = Se.get_ext_string(binary)

    {txs, binary} = decode_list(binary, &decode_tx/1)

    {%{
       serflag: serflag,
       version: version,
       height: height,
       timestamp: timestamp,
       prev_block: prev_block,
       block_commitment: block_commitment,
       block_witness: block_witness,
       sup_links: sup_links,
       txs: txs
     }, binary}
  end

  def encode_list(list, fun) when is_list(list) do
    Se.put_uvarint(length(list)) <> Enum.map_join(list, fun)
  end

  def decode_list(binary, fun) do
    {n, binary} = Se.get_uvarint(binary)
    do_decode_list(binary, n, fun, [])
  end

  defp do_decode_list(binary, 0, _fun, result), do: {Enum.reverse(result), binary}

  defp do_decode_list(binary, n, fun, result) do
    {tx, binary} = fun.(binary)
    do_decode_list(binary, n - 1, fun, [tx | result])
  end

  def encode_tx(t) do
    <<7>> <>
      Se.put_uvarint(t.version) <>
      Se.put_uvarint(t.time_range || 0) <>
      encode_list(t.inputs, &encode_input/1) <>
      encode_list(t.outputs, &encode_output/1)
  end

  @doc """
  Decode a binary format raw tx.
  """
  def decode_tx(binary) do
    <<7, binary::binary>> = binary
    {version, binary} = Se.get_uvarint(binary)
    {time_range, binary} = Se.get_uvarint(binary)

    {inputs, binary} = decode_list(binary, &decode_input/1)
    {outputs, binary} = decode_list(binary, &decode_output/1)

    {%{
       version: version,
       time_range: time_range,
       inputs: inputs,
       outputs: outputs,
       serialized_size: byte_size(binary)
     }, binary}
  end

  def encode_input(i) do
    Se.put_uvarint(i.asset_version) <>
      Se.put_ext_string(encode_input_commitment(i.commitment)) <>
      Se.put_ext_string(encode_witness(i.commitment.input_type, i.witness))
  end

  def decode_input(binary) do
    {asset_version, binary} = Se.get_uvarint(binary)
    {commitment_suffix, binary} = Se.get_ext_string(binary)
    {commitment, ""} = decode_input_commitment(commitment_suffix)

    {witness_suffix, binary} = Se.get_ext_string(binary)
    {witness, ""} = decode_witness(commitment.input_type, witness_suffix)

    {
      %{
        asset_version: asset_version,
        commitment: commitment,
        witness: witness,
        _type: input_type(commitment.input_type)
      },
      binary
    }
  end

  def encode_input_commitment(i = %{input_type: @spend_input_type}) do
    i.input_type <>
      ((i.source_id <>
          i.asset_id <>
          Se.put_uvarint(i.amount) <>
          Se.put_uvarint(i.source_position) <>
          Se.put_uvarint(i.vm_version) <>
          Se.put_ext_string(i.control_program) <>
          encode_list(i.state_data, &Se.put_ext_string/1))
       |> Se.put_ext_string())
  end

  def encode_input_commitment(i = %{input_type: <<2>>}) do
    i.input_type <>
      (i.arbitrary
       |> Se.put_ext_string())
  end

  def decode_input_commitment(binary) do
    <<input_type::binary-size(1), binary::binary>> = binary

    read_commitment(input_type, binary)
  end

  defp read_commitment(<<1>> = input_type, binary) do
    {binary, ""} = Se.get_ext_string(binary)
    <<source_id::binary-size(32), binary::binary>> = binary

    <<asset_id::binary-size(32), binary::binary>> = binary
    {amount, binary} = Se.get_uvarint(binary)

    {source_position, binary} = Se.get_uvarint(binary)

    {vm_version, binary} = Se.get_uvarint(binary)
    {control_program, binary} = Se.get_ext_string(binary)
    {state_data, binary} = decode_list(binary, &Se.get_ext_string/1)

    {%{
       input_type: input_type,
       source_id: source_id,
       asset_id: asset_id,
       amount: amount,
       source_position: source_position,
       vm_version: vm_version,
       control_program: control_program,
       state_data: state_data
     }, binary}
  end

  defp read_commitment(<<2>> = input_type, binary) do
    {arbitrary, binary} = Se.get_ext_string(binary)

    {%{
       input_type: input_type,
       arbitrary: arbitrary
     }, binary}
  end

  def encode_witness(<<1>>, w) do
    encode_list(w, &Se.put_ext_string/1)
  end

  def encode_witness(<<2>>, _w) do
    ""
  end

  def decode_witness(<<1>>, binary) do
    decode_list(binary, &Se.get_ext_string/1)
  end

  def decode_witness(<<2>>, binary) do
    {nil, binary}
  end

  def encode_output(o) do
    Se.put_uvarint(o.asset_version) <>
      o.output_type <>
      Se.put_ext_string(encode_output_commitment(o.commitment)) <>
      Se.put_ext_string(o.witness)
  end

  def decode_output(binary) do
    {asset_version, binary} = Se.get_uvarint(binary)
    <<output_type::binary-size(1), binary::binary>> = binary

    {commitment_suffix, binary} = Se.get_ext_string(binary)
    {commitment, ""} = decode_output_commitment(commitment_suffix)

    {witness, binary} = Se.get_ext_string(binary)

    {
      %{
        asset_version: asset_version,
        output_type: output_type,
        commitment: commitment,
        witness: witness,
        _type: output_type(output_type)
      },
      binary
    }
  end

  def encode_output_commitment(c) do
    c.asset_id <>
      Se.put_uvarint(c.amount) <>
      Se.put_uvarint(c.vm_version) <>
      Se.put_ext_string(c.control_program) <>
      encode_list(c.state_data, &Se.put_ext_string/1)
  end

  def decode_output_commitment(binary) do
    <<asset_id::binary-size(32), binary::binary>> = binary
    {amount, binary} = Se.get_uvarint(binary)

    {vm_version, binary} = Se.get_uvarint(binary)
    {control_program, binary} = Se.get_ext_string(binary)
    {state_data, binary} = decode_list(binary, &Se.get_ext_string/1)

    {%{
       amount: amount,
       asset_id: asset_id,
       vm_version: vm_version,
       control_program: control_program,
       state_data: state_data
     }, binary}
  end

  @doc """
  Get entry id.
  """
  def entry_id(%{_type: type} = data), do: entry_id(type, data)

  def entry_id(type, data) do
    innerhash = :crypto.hash(:sha3_256, write_for_hash(type, data))
    update = <<"entryid:">> <> get_typ(type) <> <<":">> <> innerhash
    :crypto.hash(:sha3_256, update)
  end

  defp get_typ(:issuance), do: "issuance1"
  defp get_typ(:mux), do: "mux1"
  defp get_typ(:original_output), do: "originalOutput1"
  defp get_typ(:retirement), do: "retirement1"
  defp get_typ(:spend), do: "spend1"
  defp get_typ(:tx_header), do: "txheader"

  def write_for_hash(:integer, n), do: <<n::size(64)-little>>
  def write_for_hash(:string, str), do: Se.put_ext_string(str)
  def write_for_hash(:hash, data), do: data

  def write_for_hash(type, data) do
    specs =
      case type do
        :issuance ->
          [
            nonce_hash: :hash,
            value: :asset_amount
          ]

        :asset_amount ->
          [
            asset_id: :hash,
            amount: :integer
          ]

        :mux ->
          [
            sources: [:value_source],
            program: :program
          ]

        :value_source ->
          [
            ref: :hash,
            value: :asset_amount,
            position: :integer
          ]

        :program ->
          [
            vm_version: :integer,
            code: :string
          ]

        :original_output ->
          [
            source: :value_source,
            control_program: :program,
            state_data: [:string]
          ]

        :retirement ->
          [
            source: :value_source
          ]

        :spend ->
          [
            spent_output_id: :hash
          ]

        :tx_header ->
          [
            version: :integer,
            time_range: :integer,
            result_ids: [:hash]
          ]
      end

    specs
    |> Enum.map_join(fn
      {key, [t]} ->
        write_for_hash(:list, t, data[key])

      {key, t} ->
        write_for_hash(t, data[key])
    end)
  end

  def write_for_hash(:list, type, data) do
    Se.put_uvarint(length(data)) <> Enum.map_join(data, &write_for_hash(type, &1))
  end

  def sig_hashes(tx) do
    Enum.map(tx.input_ids, fn input_id ->
      :crypto.hash(:sha3_256, input_id <> tx.id)
    end)
  end

  def spend_input(
        arguments,
        source_id,
        asset_id,
        amount,
        source_position,
        control_program,
        state_data
      ) do
    commitment = %{
      input_type: @spend_input_type,
      source_id: source_id,
      asset_id: asset_id,
      amount: amount,
      source_position: source_position,
      vm_version: 1,
      control_program: control_program,
      state_data: state_data
    }

    %{
      asset_version: 1,
      commitment: commitment,
      witness: arguments,
      _type: :spend
    }
  end

  def original_tx_output(asset_id, amount, control_program, state_data) do
    commitment = %{
      amount: amount,
      asset_id: asset_id,
      vm_version: 1,
      control_program: control_program,
      state_data: state_data
    }

    %{
      _type: :original_output,
      asset_version: 1,
      output_type: @original_output_type,
      commitment: commitment,
      witness: ""
    }
  end

  def mux(sources, program) do
    %{
      _type: :mux,
      sources: sources,
      program: program
    }
  end

  def tx_header(version, serialized_size, time_range, result_ids) do
    %{
      _type: :tx_header,
      version: version,
      serialized_size: serialized_size,
      time_range: time_range,
      result_ids: result_ids
    }
  end

  def map_tx(tx) do
    input_entries = Enum.map(Enum.with_index(tx.inputs), fn {input, i} -> map_input(input, i) end)
    input_ids = input_entries |> Enum.map(fn list -> hd(list) |> elem(0) end)

    mux = init_mux(tx, input_ids)
    mux_id = entry_id(mux)
    # TODO set destination

    output_entries =
      Enum.map(Enum.with_index(tx.outputs), fn {out, i} -> map_output(out, i, mux_id) end)

    result_ids = output_entries |> Enum.map(fn list -> hd(list) |> elem(0) end)

    # TODO mux witness destination

    %{
      tx_data: tx,
      input_ids: input_ids,
      result_ids: result_ids,
      entries:
        (input_entries ++ output_entries ++ [{mux_id, mux}]) |> List.flatten() |> Enum.into(%{})
    }
  end

  def generate_tx(mh) do
    header =
      tx_header(
        mh.tx_data.version,
        mh.tx_data.serialized_size,
        mh.tx_data.time_range,
        mh.result_ids
      )

    id = entry_id(header)

    %{
      tx_header: header,
      id: id,
      entries: Map.put(mh.entries, id, header),
      input_ids: mh.input_ids,
      spent_output_ids: ["TODO"]
    }
  end

  defp map_input(input, i) do
    case input._type do
      :spend ->
        prog = %{vm_version: input.commitment.vm_version, code: input.commitment.control_program}

        prevout =
          %{
            ref: input.commitment.source_id,
            value: %{asset_id: input.commitment.asset_id, amount: input.commitment.amount},
            position: input.commitment.source_position
          }
          |> original_output(prog, input.commitment.state_data, 0)

        prevout_id = prevout |> entry_id()
        spend = spend(prevout_id, i)

        [
          {entry_id(spend), spend},
          {prevout_id, prevout}
        ]
    end
  end

  defp asset_amount(%{commitment: %{amount: amount, asset_id: asset_id}}),
    do: %{amount: amount, asset_id: asset_id}

  defp init_mux(tx, input_ids) do
    mux_sources =
      Enum.zip(tx.inputs, input_ids)
      |> Enum.map(fn {input, id} ->
        if input._type != :coinbase do
          %{
            ref: id,
            value: asset_amount(input),
            position: 0
          }
        else
          %{
            ref: id,
            value: %{
              asset_id: btm_asset_id(),
              amount: Enum.map(tx.outputs, fn out -> out.commitment.amount end) |> Enum.sum()
            },
            position: 0
          }
        end
      end)

    mux(mux_sources, %{vm_version: 1, code: <<op_true()>>})
  end

  defp map_output(out, i, mux_id) do
    src = %{ref: mux_id, value: asset_amount(out), position: i}

    prog = %{
      vm_version: out.commitment.vm_version,
      code: out.commitment.control_program
    }

    case out._type do
      :original_output ->
        o = original_output(src, prog, out.commitment.state_data, i)

        [
          {entry_id(o), o}
        ]
    end
  end

  def original_output(source, control_program, state_data, ordinal) do
    %{
      source: source,
      control_program: control_program,
      state_data: state_data,
      ordinal: ordinal,
      _type: :original_output
    }
  end

  def spend(spent_output_id, ordinal) do
    %{
      _type: :spend,
      spent_output_id: spent_output_id,
      ordinal: ordinal
    }
  end

  def op_true, do: 0x51
end
