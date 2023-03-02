# CMD: Returns the names of the transitive dependencies of the comma-separated module names, $arg

include "library";

(moduleGraphNoVariants | removeSelfEdges) as $m |
  ($arg | split(",")) |
  transitiveDeps($m)
