/*
    Copyright © 2022, Inochi2D Project
    Distributed under the 2-Clause BSD License, see LICENSE file.

    Authors:
    - Luna Nielsen
    - Asahi Lina
*/
module creator.viewport.common.mesh;
import creator.viewport;
import inochi2d;
import inochi2d.core.dbg;
import bindbc.opengl;

struct MeshVertex {
    vec2 position;
    MeshVertex*[] connections;
    bool selected;
}

void connect(MeshVertex* self, MeshVertex* other) {
    self.connections ~= other;
    other.connections ~= self;
}
 
void disconnect(MeshVertex* self, MeshVertex* other) {
    import std.algorithm.searching : countUntil;
    import std.algorithm.mutation : remove;
    
    auto idx = other.connections.countUntil(self);
    if (idx != -1) other.connections = remove(other.connections, idx);

    idx = self.connections.countUntil(other);
    if (idx != -1) self.connections = remove(self.connections, idx);
}

void disconnectAll(MeshVertex* self) {
    while(self.connections.length > 0) {
        self.disconnect(self.connections[0]);
    }
}

bool isConnectedTo(MeshVertex* self, MeshVertex* other) {
    if (other == null) return false;

    foreach(conn; other.connections) {
        if (conn == self) return true;
    }
    return false;
}

class IncMesh {
private:
    MeshData* data;
    bool changed;

    void mImport(ref MeshData data) {
        // Reset vertex length
        vertices.length = 0;

        // Iterate over flat mesh and extract it in to
        // vertices and "connections"
        MeshVertex*[] iVertices;

        iVertices.length = data.vertices.length;
        foreach(idx, vertex; data.vertices) {
            iVertices[idx] = new MeshVertex(vertex, []);
        }

        foreach(i; 0..data.indices.length/3) {
            auto index = data.indices[i*3];
            auto nindex = data.indices[(i*3)+1];
            auto nnindex = data.indices[(i*3)+2];

            if (!iVertices[index].isConnectedTo(iVertices[nindex])) iVertices[index].connect(iVertices[nindex]);
            if (!iVertices[nindex].isConnectedTo(iVertices[nnindex])) iVertices[nindex].connect(iVertices[nnindex]);
            if (!iVertices[nnindex].isConnectedTo(iVertices[index])) iVertices[nnindex].connect(iVertices[index]);
        }
        
        void printConnections(MeshVertex* v) {
            import std.stdio;
            ushort[] conns;
            vec2[] coords;
            foreach(conn; v.connections) {
                foreach(key, value; iVertices) {
                    if (value == conn) {
                        conns ~= cast(ushort)key;
                        coords ~= value.position;
                        break;
                    }
                }
            }
        }

        foreach(i, vertex; iVertices) {
            printConnections(vertex);
            vertices ~= vertex;
        }

        refresh();
    }

    MeshData mExport() {
        import std.algorithm.searching : canFind;
        MeshData* newData = new MeshData;

        ushort[MeshVertex*] indices;
        ushort indiceIdx = 0;
        foreach(vertex; vertices) {
            newData.vertices ~= vertex.position;
            newData.uvs ~= vertex.position;
            indices[vertex] = indiceIdx++;
        }

        bool goesBackToRoot(MeshVertex* root, MeshVertex* vert) {
            foreach(MeshVertex* conn; vert.connections) {
                if (conn == root) return true;
            }
            return false;
        }

        bool hasIndiceSeq(ushort a, ushort b, ushort c) {
            foreach(i; 0..newData.indices.length/3) {
                int score = 0;

                if (newData.indices[(i*3)+0] == a || newData.indices[(i*3)+0] == b || newData.indices[(i*3)+0] == c) score++;
                if (newData.indices[(i*3)+1] == a || newData.indices[(i*3)+1] == b || newData.indices[(i*3)+1] == c) score++;
                if (newData.indices[(i*3)+2] == a || newData.indices[(i*3)+2] == b || newData.indices[(i*3)+2] == c) score++;

                if (score == 3) return true;
            }
            return false;
        }

        bool isAnyEdgeIntersecting(vec2[3] t1, vec2[3] t2) {
            vec2 t1p1, t1p2, t2p1, t2p2;
            static foreach(i; 0..3) {
                static foreach(j; 0..3) {
                    t1p1 = t1[i];
                    t1p2 = t1[(i+1)%3];
                    t2p1 = t2[j];
                    t2p2 = t2[(j+1)%3];

                    if (areLineSegmentsIntersecting(t1p1, t1p2, t2p1, t2p2)) return true;
                }
            }
            return false;
        }

        bool isIntersectingWithTris(vec2[3] t1) {
            foreach(i; 0..newData.indices.length/3) {
                vec2[3] verts = [
                    newData.vertices[newData.indices[(i*3)+0]],
                    newData.vertices[newData.indices[(i*3)+0]],
                    newData.vertices[newData.indices[(i*3)+0]]
                ];
                if (isAnyEdgeIntersecting(t1, verts)) return true;
            }
            return false;
        }

        MeshVertex*[] visited;
        void mExportVisit(MeshVertex* v) {
            visited ~= v;

            MeshVertex* findFreeIndice() {
                foreach (key; indices.keys) {
                    if (indices[key] != newData.indices[$-1] && 
                        indices[key] != newData.indices[$-2] && 
                        indices[key] != newData.indices[$-3] && 
                        !visited.canFind(key)) return cast(MeshVertex*)key;
                }
                return null;
            }

            // Second vertex
            foreach(MeshVertex* conn; v.connections) {
                if (conn == v) continue;

                // Third vertex
                foreach(MeshVertex* conn2; conn.connections) {
                    if (goesBackToRoot(v, conn2)) {

                        // Skip repeat sequences
                        if (hasIndiceSeq(indices[v], indices[conn], indices[conn2])) continue;
                        if (isIntersectingWithTris([v.position, conn.position, conn2.position])) continue;
                        

                        // Add new indices
                        newData.indices ~= [
                            indices[v],
                            indices[conn],
                            indices[conn2]
                        ];
                        break;
                    }
                }
            }

            foreach(MeshVertex* conn; v.connections) {
                if (!visited.canFind(conn)) mExportVisit(conn);
            }
        }

        // Run the export
        foreach(ref vert; vertices) {
            if (!visited.canFind(vert)) {
                mExportVisit(vert);
            }
        }

        // Save the data as the new data and refresh
        data = newData;
        reset();
        return *newData;
    }

    vec3[] points;
    vec3[] selpoints;
    vec3[] lines;
    vec3[] wlines;
    void regen() {
        points.length = 0;
        selpoints.length = 0;
        
        // Updates all point positions
        foreach(i, vert; vertices) {
            if (vert.selected) selpoints ~= vec3(vert.position, 0);
            else points ~= vec3(vert.position, 0);
        }
    }

    void regenConnections() {
        import std.algorithm.searching : canFind;

        // setup
        lines.length = 0;
        wlines.length = 0;
        MeshVertex*[] visited;
        
        // our crazy recursive func
        void recurseLines(MeshVertex* cur) {
            visited ~= cur;

            // First add the lines
            foreach(conn; cur.connections) {

                // Skip already scanned connections
                if (!visited.canFind(conn)) {
                    lines ~= [vec3(cur.position, 0), vec3(conn.position, 0)];
                }
            }
            // Then scan the next unvisited point
            foreach(conn; cur.connections) {

                // Skip already scanned connections
                if (!visited.canFind(conn)) {
                    recurseLines(conn);
                }
            }
        }

        foreach(ref vert; vertices) {
            if (!visited.canFind(vert)) {
                recurseLines(vert);
            }
        }
    }

public:
    MeshVertex*[] vertices;

    /**
        Constructs a new IncMesh
    */
    this(ref MeshData mesh) {
        import_(mesh);
    }

    final
    void import_(ref MeshData mesh) {
        data = &mesh;
        mImport(mesh);
    }
    
    /**
        Exports the working mesh to a MeshData object.
    */
    final
    MeshData export_() {
        return mExport();
    }

    /**
        Resets mesh to prior state
    */
    void reset() {
        mImport(*data);
        refresh();
    }

    /**
        Clears the mesh of everything
    */
    void clear() {
        vertices.length = 0;
        refresh();
    }

    /**
        Refreshes graphical portion of the mesh
    */
    void refresh() {
        regen();
        regenConnections();
    }

    /**
        Draws the mesh
    */
    void draw(mat4 trans = mat4.identity) {
        if (lines.length > 0) {
            inDbgSetBuffer(lines);
            inDbgDrawLines(vec4(0.7, 0.7, 0.7, 1), trans);
        }

        if (wlines.length > 0) {
            inDbgSetBuffer(lines);
            inDbgDrawLines(vec4(0.7, 0.2, 0.2, 1), trans);
        }

        if (points.length > 0) {
            inDbgSetBuffer(points);
            inDbgPointsSize(10);
            inDbgDrawPoints(vec4(0, 0, 0, 1), trans);
            inDbgPointsSize(6);
            inDbgDrawPoints(vec4(1, 1, 1, 1), trans);
        }

        if (selpoints.length > 0) {
            inDbgSetBuffer(selpoints);
            inDbgPointsSize(10);
            inDbgDrawPoints(vec4(0, 0, 0, 1), trans);
            inDbgPointsSize(6);
            inDbgDrawPoints(vec4(1, 0, 0, 1), trans);
        }
    }

    bool isPointOverVertex(vec2 point) {
        foreach(vert; vertices) {
            if (abs(vert.position.distance(point)) < 12f/incViewportZoom) return true;
        }
        return false;
    }

    void removeVertexAt(vec2 point) {
        foreach(i; 0..vertices.length) {
            if (abs(vertices[i].position.distance(point)) < 12f/incViewportZoom) {
                this.remove(vertices[i]);
                return;
            }
        }
    }

    MeshVertex* getVertexFromPoint(vec2 point) {
        foreach(ref vert; vertices) {
            if (abs(vert.position.distance(point)) < 12f/incViewportZoom) return vert;
        }
        return null;
    }

    void remove(MeshVertex* vert) {
        import std.algorithm.searching : countUntil;
        import std.algorithm.mutation : remove;
        
        auto idx = vertices.countUntil(vert);
        if (idx != -1) {
            disconnectAll(vert);
            vertices = vertices.remove(idx);
        }
    }

    vec2[] getOffsets() {
        vec2[] offsets;

        offsets.length = vertices.length;
        foreach(idx, vertex; vertices) {
            offsets[idx] = vertex.position - data.vertices[idx];
        }
        return offsets;
    }

    void applyOffsets(vec2[] offsets) {
        foreach(idx, vertex; vertices) {
            vertex.position += offsets[idx];
        }
        regen();
        regenConnections();
    }

    /**
        Flips all vertices horizontally
    */
    void flipHorz() {
        foreach(ref vert; vertices) {
            vert.position.x *= -1;
        }
        refresh();
    }

    /**
        Flips all vertices vertically
    */
    void flipVert() {
        foreach(ref vert; vertices) {
            vert.position.y *= -1;
        }
        refresh();
    }
}