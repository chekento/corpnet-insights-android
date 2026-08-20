import * as d3 from 'd3';

export class NetworkGraph {
    constructor(containerId, onNodeClick) {
        this.container = document.getElementById(containerId);
        this.onNodeClick = onNodeClick;
        this.width = this.container.clientWidth;
        this.height = this.container.clientHeight;
        
        this.svg = d3.select(`#${containerId}`)
            .append("svg")
            .attr("width", "100%")
            .attr("height", "100%")
            .attr("viewBox", [0, 0, this.width, this.height]);

        this.g = this.svg.append("g");

        this.zoom = d3.zoom()
            .scaleExtent([0.05, 4])
            .on("zoom", (event) => {
                this.g.attr("transform", event.transform);
            });

        this.svg.call(this.zoom);

        this.simulation = d3.forceSimulation()
            .force("link", d3.forceLink().id(d => d.id).distance(140)) 
            .force("charge", d3.forceManyBody().strength(-1200))
            .force("center", d3.forceCenter(this.width / 2, this.height / 2))
            .force("collision", d3.forceCollide().radius(70)) 
            .force("x", d3.forceX().strength(0.04)) 
            .force("y", d3.forceY().strength(0.04));

        this.colors = {
            main: "#3b82f6",
            parent: "#f59e0b",
            sister: "#06b6d4",
            subsidiary: "#a855f7",
            partner: "#10b981",
            competitor: "#ef4444",
            supplier: "#64748b"
        };

        const defs = this.svg.append("defs");
        defs.append("marker")
            .attr("id", "arrow-head")
            .attr("viewBox", "0 -5 10 10")
            .attr("refX", 32)
            .attr("refY", 0)
            .attr("markerWidth", 6)
            .attr("markerHeight", 6)
            .attr("orient", "auto")
            .append("path")
            .attr("d", "M0,-5L10,0L0,5")
            .attr("fill", "#475569");

        window.addEventListener('resize', () => this.handleResize());
    }

    handleResize() {
        this.width = this.container.clientWidth;
        this.height = this.container.clientHeight;
        this.svg.attr("width", this.width).attr("height", this.height);
        this.simulation.force("center", d3.forceCenter(this.width / 2, this.height / 2));
    }

    render(nodes, links) {
        if (this.simulation) this.simulation.stop();
        this.g.selectAll("*").remove();

        const link = this.g.append("g")
            .attr("class", "links")
            .selectAll("line")
            .data(links)
            .enter().append("line")
            .attr("class", "link")
            .attr("stroke", d => {
                if (d.type === 'competitor') return "#ef4444";
                if (d.type === 'parent') return "#fbbf24";
                return "#475569";
            })
            .attr("stroke-opacity", d => {
                if (d.type === 'parent' || d.type === 'subsidiary') return 0.6;
                if (d.type === 'competitor') return 0.3;
                return 0.4;
            })
            .attr("stroke-width", d => {
                if (d.type === 'parent') return 3;
                if (d.type === 'subsidiary') return 2.5;
                if (d.type === 'sister') return 2;
                return 1;
            })
            .attr("stroke-dasharray", d => d.type === 'partner' || d.type === 'competitor' ? "4,4" : "0")
            .attr("marker-end", d => (d.type === 'parent' || d.type === 'subsidiary') ? "url(#arrow-head)" : null);

        const node = this.g.append("g")
            .attr("class", "nodes")
            .selectAll("g")
            .data(nodes)
            .enter().append("g")
            .attr("class", "node")
            .call(d3.drag()
                .on("start", (e, d) => this.dragstarted(e, d))
                .on("drag", (e, d) => this.dragged(e, d))
                .on("end", (e, d) => this.dragended(e, d)))
            .on("click", (e, d) => this.onNodeClick(d));

        node.filter(d => d.type === 'main' || d.type === 'parent')
            .append("circle")
            .attr("r", d => d.type === 'main' ? 55 : 45)
            .attr("fill", d => this.colors[d.type])
            .attr("opacity", 0.15)
            .attr("class", "pulse-ring");

        node.append("circle")
            .attr("r", d => {
                if(d.type === 'main') return 40;
                if(d.type === 'parent') return 35;
                if(d.type === 'subsidiary' || d.type === 'sister') return 25;
                return 20;
            })
            .attr("fill", d => this.colors[d.type] || "#64748b")
            .attr("stroke", "#0f172a")
            .attr("stroke-width", 2)
            .attr("class", "node-circle shadow-lg");

        node.append("text")
            .attr("dy", d => {
                if(d.type === 'main') return 60;
                if(d.type === 'parent') return 55;
                if(d.type === 'subsidiary' || d.type === 'sister') return 45;
                return 35;
            })
            .attr("text-anchor", "middle")
            .attr("fill", "#f8fafc")
            .attr("font-size", "10px")
            .attr("font-weight", "600")
            .text(d => d.name);

        this.simulation.nodes(nodes).on("tick", () => {
            link
                .attr("x1", d => d.source.x)
                .attr("y1", d => d.source.y)
                .attr("x2", d => d.target.x)
                .attr("y2", d => d.target.y);

            node.attr("transform", d => `translate(${d.x},${d.y})`);
        });

        this.simulation.force("link").links(links);
        this.simulation.alpha(1).restart();
    }

    dragstarted(event, d) {
        if (!event.active) this.simulation.alphaTarget(0.3).restart();
        d.fx = d.x;
        d.fy = d.y;
    }

    dragged(event, d) {
        d.fx = event.x;
        d.fy = event.y;
    }

    dragended(event, d) {
        if (!event.active) this.simulation.alphaTarget(0);
        d.fx = null;
        d.fy = null;
    }

    zoomIn() { this.svg.transition().call(this.zoom.scaleBy, 1.3); }
    zoomOut() { this.svg.transition().call(this.zoom.scaleBy, 0.7); }
    resetZoom() { this.svg.transition().call(this.zoom.transform, d3.zoomIdentity); }

    setFilters(activeTypes) {
        const isFiltering = activeTypes && activeTypes.size > 0;
        this.g.selectAll(".node")
            .transition()
            .duration(300)
            .style("opacity", d => !isFiltering ? 1 : (activeTypes.has(d.type) ? 1 : 0.05))
            .style("pointer-events", d => !isFiltering ? "all" : (activeTypes.has(d.type) ? "all" : "none"));

        this.g.selectAll(".link")
            .transition()
            .duration(300)
            .style("opacity", d => {
                if (!isFiltering) {
                    if (d.type === 'parent' || d.type === 'subsidiary') return 0.6;
                    if (d.type === 'competitor') return 0.3;
                    return 0.4;
                }
                const sourceActive = activeTypes.has(d.source.type);
                const targetActive = activeTypes.has(d.target.type);
                return (sourceActive && targetActive) ? 0.8 : 0.02;
            });
    }
}
