require File.expand_path(File.dirname(__FILE__) + '/test_helper')
# Warning: ugly...

class XYZ
  include Packable
  def write_packed(io, options)
    io << "xyz"
  end
  def self.unpack_string(s, options)
    raise "baddly packed XYZ: #{s}" unless "xyz" == s
    XYZ.new
  end
end

class TestingPack < Minitest::Test

  context "Original form" do
    should "pack like before" do
      assert_equal "a  \000\000\000\001", ["a",1,66].pack("A3N")
    end

    should "be equivalent to new form" do
      assert_equal ["a",1,2.34, 66].pack({:bytes=>3}, {:bytes=>4, :endian=>:big}, {:precision=>:double, :endian=>:big}), ["a",1,2.34, 66].pack("A3NG")
    end
  end

  def test_shortcuts
    assert_equal 0x123456.pack(:short), 0x123456.pack(:bytes => 2)
    assert_equal 0x3456, 0x123456.pack(:short).unpack(:short)
  end

  def test_custom_form
    assert_equal "xyz", XYZ.new.pack
    assert_equal XYZ, "xyz".unpack(XYZ).class
  end

  def test_pack_default
    assert_equal "\000\000\000\006", 6.pack
    assert_equal "abcd", "abcd".pack
    assert_equal "\000\000\000\006abcd", [6,"abcd"].pack
    String.packers.set :flv_signature, :bytes => 3, :fill => "FLV"
    assert_equal "xFL", "x".pack(:flv_signature)
  end

  def test_integer
    assert_equal "\002\001\000", 258.pack(:bytes => 3, :endian => :little)
    assert_equal 258, Integer.unpack("\002\001\000", :bytes => 3, :endian => :little)
    assert_equal (1<<24)-1, -1.pack(:bytes => 3).unpack(Integer, :bytes => 3, :signed => false)
    assert_equal -1, -1.pack(:bytes => 3).unpack(Integer, :bytes => 3, :signed => true)
    assert_equal 42, 42.pack('L').unpack(Integer, :bytes => 4, :endian => :native)
    assert_raises(ArgumentError){ 42.pack(:endian => "Geronimo")}
  end

  def test_bignum
    assert_equal 1.pack(:long), ((1 << 69) + 1).pack(:long)
    assert_equal "*" + ("\000" * 15), (42 << (8*15)).pack(:bytes => 16)
    assert_equal 42 << (8*15), (42 << (8*15)).pack(:bytes => 16).unpack(Integer, :bytes => 16)
  end

  def test_float
    assert_raises(ArgumentError){ Math::PI.pack(:endian => "Geronimo")}
    assert_equal Math::PI, Math::PI.pack(:precision => :double, :endian => :native).unpack(Float, :precision => :double, :endian => :native)
    # Issue #1
    assert_equal Math::PI.pack(:precision => :double), Math::PI.pack('G')
    assert_equal Math::PI.pack(:precision => :single), Math::PI.pack('g')
    assert_equal Math::PI.pack(:precision => :double), Math::PI.pack('G')
  end

  def test_io
    io = StringIO.new("\000\000\000\006abcdE!")
    n, s, c = io >> [Integer, {:signed=>false}] >> [String, {:bytes => 4}] >> :char
    assert_equal 6, n
    assert_equal "abcd", s
    assert_equal 69, c
    assert_equal "!", io.read
  end

  def test_io_read_nil
    # library was failing to call read_without_packing when invoked with nil.
    io = StringIO.new("should read(nil)")
    assert_equal "should read(nil)", io.read(nil)
  end

  def test_io_read_to_outbuf
    # library was failing to call read_without_packing when invoked with fixnum and output buffer.
    io = StringIO.new("should read(fixnum, buf)")
    io.read(11, outbuf='')
    assert_equal "should read", outbuf
  end

  should "do basic type checking" do
    assert_raises(TypeError) {"".unpack(42, :short)}
  end

  context "Reading beyond the eof" do
    should "raises an EOFError when reading" do
      ["", "x"].each do |s|
        io = StringIO.new(s)
        assert_raises(EOFError) {io.read(:double)}
        assert_raises(EOFError) {io.read(:short)}
        assert_raises(EOFError) {io.read(String, :bytes => 4)}
      end
    end

    should "return nil for unpacking" do
      assert_nil "".unpack(:double)
      assert_nil "".unpack(:short)
      assert_nil "x".unpack(:double)
      assert_nil "x".unpack(:short)
    end
  end

  context "Filters" do
    context "for Object" do
      Object.packers.set :generic_class_writer do |packer|
        packer.write do |io|
          io << self.class.name << self
        end
      end
      should "be follow accessible everywhere" do
        assert_equal "StringHello", "Hello".pack(:generic_class_writer)
        assert_match /Integer\x00\x00\x00\x06$/, 6.pack(:generic_class_writer)
      end
    end
    context "for a specific class" do
      String.packers.set :specific_writer do |packer|
        packer.write do |io|
          io << "Hello"
        end
      end

      should "be accessible only from that class and descendants" do
        assert_equal "Hello", "World".pack(:specific_writer)
        assert_raises RuntimeError do
          6.pack(:specific_writer)
        end
      end
    end
  end

end
