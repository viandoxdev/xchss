define pmove
	printf "(%u) %u:%u [%u]\n", ($arg0 >> 6), ($arg0 >> 3) & 0b111, $arg0 & 0b111, ($arg0 >> 1) & 0b111 
end
