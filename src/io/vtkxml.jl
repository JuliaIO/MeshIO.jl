
using LightXML
using Codecs

export exportBinaryCompressedVTKXML,
       exportBinaryVTKXML,
       exportASCIIVTKXML

const COMPRESS_LEVEL = 5
const TRIANGLE_VTK = 5
const NTRIGVERTS = 3


const vtk_ascii = FileEnding{:vtkxml_ascii}(:vtkxml, b"<?xml version=\"1.0\" encoding=\"utf-8\"?>\n
<VTKFile type=\"UnstructuredGrid\" version=\"0.1\" byte_order=\"LittleEndian\">")
# No real way to tell the difference from an ascii vtkxml from header. Binary / Ascii can be changed arbitrarily from
# data section to data section.
const vtk_binary = FileEnding{:vtkxml_binary}(:vtkxml, b"<?xml version=\"1.0\" encoding=\"utf-8\"?>\n
<VTKFile type=\"UnstructuredGrid\" version=\"0.1\" byte_order=\"LittleEndian\">")

const vtk_binarycompressed = FileEnding{:vtkxml_binarycompressed}(:vtkxml, b"<?xml version=\"1.0\" encoding=\"utf-8\"?>\n
<VTKFile type=\"UnstructuredGrid\" version=\"0.1\" byte_order=\"LittleEndian\" compressor=\"vtkZLibDataCompressor\">")


#Long names in spirit of the VTK library :)
abstract AbstractVTKXMLWriter

abstract AbstractVTKXMLBinaryWriter <: AbstractVTKXMLWriter

type VTKXMLBinaryCompressedWriter <: AbstractVTKXMLBinaryWriter
    buffer::IOBuffer
end

type VTKXMLBinaryUncompressedWriter <: AbstractVTKXMLBinaryWriter
    buffer::IOBuffer
end

type VTKXMLASCIIWriter <: AbstractVTKXMLWriter
    buffer::IOBuffer
end

VTKXMLBinaryCompressedWriter() = VTKXMLBinaryCompressedWriter(IOBuffer())
VTKXMLBinaryUncompressedWriter() = VTKXMLBinaryUncompressedWriter(IOBuffer())

VTKXMLASCIIWriter() = VTKXMLASCIIWriter(IOBuffer())

add_data!(vtkw::VTKXMLASCIIWriter, data) = print(buffer(vtkw), data, " ")
add_data!(vtkw::AbstractVTKXMLBinaryWriter, data) = write(buffer(vtkw), data)

function add_data!{T}(vtkw::VTKXMLASCIIWriter, data::AbstractArray{T})
    for c in data
        add_data!(vtkw, c)
    end
end

iscompressing(::AbstractVTKXMLWriter) = false
iscompressing(::VTKXMLBinaryCompressedWriter) = true

isbinary(::AbstractVTKXMLBinaryWriter) = true
isbinary(::VTKXMLASCIIWriter) = false

buffer(v::AbstractVTKXMLWriter) = v.buffer


function write_data!(vtkw::VTKXMLBinaryCompressedWriter, xmlele::XMLElement)
    data_array = takebuf_array(buffer(vtkw))
    uncompressed_size = length(data_array)
    compressed_data = compress(data_array, COMPRESS_LEVEL)
    compressed_size = length(compressed_data)
    header = UInt32[1, uncompressed_size, uncompressed_size, compressed_size]
    header_binary = bytestring(encode(Base64, reinterpret(UInt8, header)))
    data_binary = bytestring(encode(Base64, compressed_data))
    add_text(xmlele, header_binary)
    add_text(xmlele, data_binary)
end

function write_data!(vtkw::VTKXMLBinaryUncompressedWriter, xmlele::XMLElement)
    data_array = takebuf_array(buffer(vtkw))
    uncompressed_size = length(data_array)
    header = UInt32[uncompressed_size]
    header_binary = bytestring(encode(Base64, reinterpret(UInt8, header)))
    data_binary = bytestring(encode(Base64, data_array))
    add_text(xmlele, header_binary)
    add_text(xmlele, data_binary)
end


Base.write(fn::File{:vtkxml_binarycompressed}, msh::Mesh) = write_vtkxml(mesh, VTKXMLBinaryCompressedWriter())
Base.write(fn::File{:vtkxml_binary}, msh::Mesh) = write_vtkxml(mesh, VTKXMLBinaryUncompressedWriter())
Base.write(fn::File{:vtkxml_ascii}, msh::Mesh) = write_vtkxml(mesh, VTKXMLASCIIWriter())

function Base.write(msh::Mesh, vtkwriter::AbstractVTKXMLWriter)

    vts = msh[Point3{Float32}]
    nV = length(vts)
    fcs = msh[Face3{Int32, -1}]
    nF = length(fcs)

    if isbinary(vtkwriter)
        VTK_FORMAT = "binary"
    else
        VTK_FORMAT = "ascii"
    end

    xdoc = XMLDocument()
    xroot = create_root(xdoc, "VTKFile")
    set_attribute(xroot, "type", "UnstructuredGrid")
    set_attribute(xroot, "version", "0.1")
    set_attribute(xroot, "byte_order", "LittleEndian")

    if vtkexp.compress
        set_attribute(xroot, "compressor", "vtkZLibDataCompressor")
    end

    xgrid = new_child(xroot, "PolyData")
    xpiece = new_child(xgrid, "Piece")

    set_attribute(xpiece, "NumberOfPoints", nV)
    set_attribute(xpiece, "NumberOfCells", nF)

    # Points
    xpoints = new_child(xpiece, "Points")

    # Coordinates for points
    xcoords = new_child(xpoints, "DataArray")
    set_attribute(xcoords, "type", "Float64")
    set_attribute(xcoords, "name", "Points")
    set_attribute(xcoords, "format", VTK_FORMAT)
    set_attribute(xcoords, "NumberOfComponents", "3")

    for v in vts
        add_data!(vtkw, v)
    end
    write_data!(vtkw, xcoords)

    # Cells
    xcells = new_child(xpiece, "Cells")

    # Cell connectivity
    xcellconn = new_child(xcells, "DataArray")
    set_attribute(xcellconn, "type", "Int64")
    set_attribute(xcellconn, "Name", "connectivity")
    set_attribute(xcellconn, "format", VTK_FORMAT)

    for f in fcs
        add_data!(vtkw, f)
    end
    write_data!(vtkw, xcellconn)

    # Cell location data
    xcell_offsets = new_child(xcells, "DataArray")
    set_attribute(xcell_offsets, "type", "Int64")
    set_attribute(xcell_offsets, "Name", "offsets")
    set_attribute(xcell_offsets, "format", VTK_FORMAT)
    offsets = collect(NTRIGVERTS:NTRIGVERTS:NTRIGVERTS * nF)
    add_data!(vtkw, offsets)
    write_data!(vtkw, xcell_offsets)

    # Cell type data
    xcell_types = new_child(xcells, "DataArray")
    set_attribute(xcell_types, "type", "UInt8")
    set_attribute(xcell_types, "Name", "types")
    set_attribute(xcell_types, "format", VTK_FORMAT)
    cell_types = UInt8[TRIANGLE_VTK  for _ in 1:length(section.elements)]
    add_data!(vtkw, cell_types)
    write_data!(vtkw, xcell_types)

    free(xroot)
end
