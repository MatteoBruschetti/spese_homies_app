/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState, useEffect, useRef } from 'react';
import {
  ChakraProvider,
  Box,
  VStack,
  HStack,
  Text,
  Button,
  Input,
  SimpleGrid,
  Container,
  Heading,
  Stat,
  StatLabel,
  StatNumber,
  List,
  ListItem,
  IconButton,
  Divider,
  useToast,
  Modal,
  ModalOverlay,
  ModalContent,
  ModalHeader,
  ModalFooter,
  ModalBody,
  ModalCloseButton,
  useDisclosure,
  Flex,
  Center,
  Avatar,
  Badge,
} from '@chakra-ui/react';
import { supabase, Expense, Settlement } from './lib/supabase';

// --- Constants ---
const CATEGORIES = [
  { name: 'Spesa', emoji: '🛒' },
  { name: 'Ristorante', emoji: '🍴' },
  { name: 'Casa', emoji: '🏠' },
  { name: 'Utenze', emoji: '🔌' },
  { name: 'Svago', emoji: '🎮' },
  { name: 'Viaggio', emoji: '✈️' },
];

const HIDDEN_DEFAULT_CATEGORY = { name: 'Altro', emoji: '❓' };

// --- Hooks ---
function useUserIdentity() {
  const [user, setUser] = useState<string | null>(localStorage.getItem('user_name'));

  useEffect(() => {
    if (!user) {
      const ua = navigator.userAgent.toLowerCase();
      const isIOS = /iphone|ipad|ipod/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
      const isAndroid = /android/.test(ua);
      
      let detectedUser = 'Matteo'; // Default fallback
      if (isIOS) {
        detectedUser = 'Elena';
      } else if (isAndroid) {
        detectedUser = 'Matteo';
      }

      localStorage.setItem('user_name', detectedUser);
      setUser(detectedUser);
    }
  }, [user]);

  return user;
}

// --- Types ---
type Tab = 'ADD' | 'HISTORY' | 'BALANCE';

export default function App() {
  const userName = useUserIdentity();
  const [activeTab, setActiveTab] = useState<Tab>('ADD');
  const toast = useToast({
    position: 'top',
    isClosable: true,
    duration: 3000,
  });

  if (!userName) return null;

  return (
    <ChakraProvider>
      <Box bg="gray.50" minH="100vh" pb="120px">
        <Container maxW="container.sm" pt={8} px={6}>
          {/* Header */}
          <Flex justify="space-between" align="center" mb={10}>
            <VStack align="start" spacing={0}>
              <Heading size="lg" fontWeight="bold" letterSpacing="tight">
                Spese di Coppia 💖
              </Heading>
              <Text color="gray.500" fontSize="sm">
                Bentornato, <Box 
                  as="span" 
                  fontWeight="semibold" 
                  color="blue.600" 
                  cursor="pointer"
                  _hover={{ color: 'blue.400', textDecoration: 'underline' }}
                  onClick={() => {
                    const newUser = userName === 'Matteo' ? 'Elena' : 'Matteo';
                    localStorage.setItem('user_name', newUser);
                    window.location.reload();
                  }}
                >
                  {userName}
                </Box>! 👋
              </Text>
            </VStack>
          </Flex>

          {/* Main Content */}
          <Box minH="60vh">
            {activeTab === 'ADD' && <TabAdd userName={userName} toast={toast} />}
            {activeTab === 'HISTORY' && <TabHistory userName={userName} />}
            {activeTab === 'BALANCE' && <TabBalance userName={userName} toast={toast} />}
          </Box>
        </Container>

        {/* Bottom Navigation */}
        <Box 
          position="fixed" 
          bottom={6} 
          left={6} 
          right={6} 
          bg="rgba(255, 255, 255, 0.9)" 
          backdropFilter="blur(10px)"
          borderWidth="1px" 
          borderColor="gray.100"
          borderRadius="3xl"
          boxShadow="0 10px 25px -5px rgba(0, 0, 0, 0.1)"
          zIndex={10}
        >
          <HStack spacing={0} justify="space-around" height="80px">
            <NavButton 
              isActive={activeTab === 'ADD'} 
              label="Aggiungi" 
              emoji="⚡" 
              onClick={() => setActiveTab('ADD')} 
            />
            <NavButton 
              isActive={activeTab === 'HISTORY'} 
              label="Storico" 
              emoji="📊" 
              onClick={() => setActiveTab('HISTORY')} 
            />
            <NavButton 
              isActive={activeTab === 'BALANCE'} 
              label="Bilancio" 
              emoji="⚖️" 
              onClick={() => setActiveTab('BALANCE')} 
            />
          </HStack>
        </Box>
      </Box>
    </ChakraProvider>
  );
}

// --- Sub-components (Tabs) ---

function NavButton({ isActive, label, emoji, onClick }: { isActive: boolean, label: string, emoji: string, onClick: () => void }) {
  return (
    <VStack 
      as="button" 
      onClick={onClick} 
      spacing={1} 
      flex={1} 
      color={isActive ? 'blue.600' : 'gray.400'}
      transition="all 0.2s"
      transform={isActive ? 'scale(1.1)' : 'scale(1)'}
    >
      <Text fontSize="2xl">{emoji}</Text>
      <Text fontSize="xs" fontWeight={isActive ? '800' : 'bold'}>{label}</Text>
    </VStack>
  );
}

function TabAdd({ userName, toast }: { userName: string, toast: ReturnType<typeof useToast> }) {
  const [amount, setAmount] = useState('');
  const [selectedCategory, setSelectedCategory] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  const handleAdd = async () => {
    const cleanAmount = typeof amount === 'string' ? amount.replace(',', '.') : amount;
    const numAmount = parseFloat(cleanAmount);
    
    if (isNaN(numAmount) || numAmount <= 0) {
      toast({ title: 'Inserisci una cifra valida', status: 'error', variant: 'subtle' });
      return;
    }

    setLoading(true);
    try {
      const { error } = await supabase.from('expenses').insert({
        amount: numAmount,
        category: selectedCategory || 'Altro',
        created_by: userName,
      });

      if (error) throw error;

      toast({ title: 'Spesa aggiunta! ⚡', status: 'success', duration: 2000 });
      setAmount('');
      setSelectedCategory(null);
    } catch (error: any) {
      console.error('Error adding expense:', error);
      toast({ 
        title: 'Errore durante il salvataggio', 
        description: error.message || 'Errore di connessione al database', 
        status: 'error' 
      });
    } finally {
      setLoading(false);
    }
  };

  return (
    <VStack spacing={6} align="stretch" bg="white" p={8} borderRadius="3xl" shadow="sm" border="1px solid" borderColor="gray.100">
      <HStack spacing={3} mb={2}>
        <Text fontSize="xl">⚡</Text>
        <Heading size="md" fontWeight="bold">Aggiungi Spesa</Heading>
      </HStack>

      <VStack align="stretch" spacing={2}>
        <Text fontSize="xs" fontWeight="bold" color="gray.400" textTransform="uppercase">Importo</Text>
        <Box position="relative">
          <Text position="absolute" left={5} top="50%" transform="translateY(-50%)" fontSize="3xl" fontWeight="bold" color="gray.400" fontFamily="mono">
            €
          </Text>
          <Input
            ref={inputRef}
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder="0,00"
            variant="unstyled"
            bg="gray.50"
            p={8}
            pl={12}
            borderRadius="2xl"
            fontSize="4xl"
            fontFamily="mono"
            fontWeight="bold"
            color="blue.600"
            type="text"
            inputMode="decimal"
            _placeholder={{ color: 'gray.300' }}
          />
        </Box>
      </VStack>

      <VStack align="stretch" spacing={3}>
        <Text fontSize="xs" fontWeight="bold" color="gray.400" textTransform="uppercase">Categoria</Text>
        <SimpleGrid columns={2} spacing={3}>
          {CATEGORIES.map((cat) => (
            <Button
              key={cat.name}
              height="80px"
              variant="outline"
              borderRadius="2xl"
              onClick={() => setSelectedCategory(cat.name)}
              border="2px solid"
              borderColor={selectedCategory === cat.name ? 'blue.100' : 'gray.100'}
              bg={selectedCategory === cat.name ? 'blue.50' : 'white'}
              color={selectedCategory === cat.name ? 'blue.700' : 'gray.600'}
              transition="all 0.2s"
              _hover={{ bg: selectedCategory === cat.name ? 'blue.100' : 'gray.50' }}
              flexDirection="column"
            >
              <Text fontSize="2xl" mb={1}>{cat.emoji}</Text>
              <Text fontSize="sm" fontWeight={selectedCategory === cat.name ? 'bold' : 'medium'}>{cat.name}</Text>
            </Button>
          ))}
        </SimpleGrid>
      </VStack>

      <Button
        size="lg"
        colorScheme="blue"
        height="70px"
        fontSize="lg"
        fontWeight="bold"
        borderRadius="2xl"
        isLoading={loading}
        onClick={handleAdd}
        boxShadow="0 10px 20px -5px rgba(66, 153, 225, 0.4)"
        mt={4}
      >
        Aggiungi Ora
      </Button>
    </VStack>
  );
}

function TabHistory({ userName }: { userName: string }) {
  const [expenses, setExpenses] = useState<Expense[]>([]);
  const [loading, setLoading] = useState(true);

  const fetchExpenses = async () => {
    setLoading(true);
    try {
      const { data, error } = await supabase
        .from('expenses')
        .select('*')
        .order('created_at', { ascending: true });

      if (error) throw error;
      if (data) setExpenses(data);
    } catch (error: any) {
      console.error('Error fetching expenses:', error);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchExpenses();
  }, []);

  const deleteExpense = async (id: string) => {
    try {
      const { error } = await supabase.from('expenses').delete().eq('id', id);
      if (error) throw error;
      fetchExpenses();
    } catch (error: any) {
      console.error('Error deleting expense:', error);
    }
  };

  // Calcolo medie reali
  const totalsByPeriod = expenses.reduce((acc, exp) => {
    const d = new Date(exp.created_at);
    const monthKey = `${d.getMonth()}-${d.getFullYear()}`;
    const yearKey = `${d.getFullYear()}`;
    acc.monthly[monthKey] = (acc.monthly[monthKey] || 0) + exp.amount;
    acc.yearly[yearKey] = (acc.yearly[yearKey] || 0) + exp.amount;
    return acc;
  }, { monthly: {} as Record<string, number>, yearly: {} as Record<string, number> });

  const monthlyValues = Object.values(totalsByPeriod.monthly) as number[];
  const monthlySum = monthlyValues.reduce((a, b) => a + b, 0);
  const monthlyAvg = Object.keys(totalsByPeriod.monthly).length > 0
    ? monthlySum / Object.keys(totalsByPeriod.monthly).length
    : 0;

  const yearlyValues = Object.values(totalsByPeriod.yearly) as number[];
  const yearlySum = yearlyValues.reduce((a, b) => a + b, 0);
  const yearlyAvg = Object.keys(totalsByPeriod.yearly).length > 0
    ? yearlySum / Object.keys(totalsByPeriod.yearly).length
    : 0;

  // Stats by category (including "Altro")
  const allPossibleCategories = [...CATEGORIES, HIDDEN_DEFAULT_CATEGORY];
  const catStats = allPossibleCategories.map(cat => {
    const total = expenses
      .filter(e => e.category === cat.name)
      .reduce((sum: number, e: Expense) => sum + e.amount, 0);
    return { ...cat, total };
  }).filter(c => c.total > 0);

  return (
    <VStack spacing={6} align="stretch">
      {/* Stats Section */}
      <Box bg="white" p={6} borderRadius="3xl" shadow="sm" border="1px solid" borderColor="gray.100">
        <Heading size="md" mb={4} fontWeight="bold">Riepilogo spese</Heading>
        <SimpleGrid columns={2} spacing={4}>
          <Box p={4} bg="blue.50" borderRadius="2xl">
            <Text fontSize="10px" fontWeight="black" color="blue.600" textTransform="uppercase" mb={1}>Media mensile</Text>
            <Text fontSize="2xl" fontWeight="bold">€{monthlyAvg.toFixed(2)}</Text>
          </Box>
          <Box p={4} bg="green.50" borderRadius="2xl">
            <Text fontSize="10px" fontWeight="black" color="green.600" textTransform="uppercase" mb={1}>Media annuale</Text>
            <Text fontSize="2xl" fontWeight="bold">€{yearlyAvg.toFixed(2)}</Text>
          </Box>
        </SimpleGrid>

        <Text fontSize="xs" fontWeight="bold" color="gray.400" textTransform="uppercase" mb={3} mt={6}>Per Categoria</Text>
        <HStack overflowX="auto" pb={2} spacing={4}>
          {catStats.length > 0 ? catStats.map(cat => (
            <VStack key={cat.name} align="start" minW="100px" bg="gray.50" p={3} borderRadius="xl">
              <Text fontSize="xs" color="gray.500">{cat.emoji} {cat.name}</Text>
              <Text fontWeight="bold" fontSize="md">€{cat.total.toFixed(0)}</Text>
            </VStack>
          )) : <Text fontSize="xs" color="gray.400">Nessuna categoria.</Text>}
        </HStack>
      </Box>

      {/* Timeline Section */}
      <Box bg="white" p={6} borderRadius="3xl" shadow="sm" border="1px solid" borderColor="gray.100" flex={1}>
        <Flex justify="space-between" align="center" mb={6}>
          <Heading size="md" fontWeight="bold">Timeline</Heading>
        </Flex>

        {loading ? (
          <Center py={10}><Text color="gray.400">Caricamento...</Text></Center>
        ) : expenses.length === 0 ? (
          <Center py={10}><Text color="gray.400">Ancora nessuna spesa.</Text></Center>
        ) : (
          <VStack spacing={3} align="stretch">
            {(() => {
              let lastMonthLabel = '';
              return expenses.map((exp, index) => {
                const expDate = new Date(exp.created_at);
                const currentMonthLabel = expDate.toLocaleDateString('it-IT', { month: 'long', year: 'numeric' }).toUpperCase();
                const showMonthLabel = currentMonthLabel !== lastMonthLabel;
                lastMonthLabel = currentMonthLabel;

                return (
                  <React.Fragment key={exp.id}>
                    {showMonthLabel && (
                      <Box pt={index === 0 ? 0 : 6} pb={2}>
                        <Badge colorScheme="gray" variant="subtle" px={3} py={1} borderRadius="lg" fontSize="10px" fontWeight="black">
                          {currentMonthLabel}
                        </Badge>
                      </Box>
                    )}
                    <Flex 
                      bg="gray.50" 
                      p={4} 
                      borderRadius="2xl" 
                      align="center" 
                      justify="space-between"
                    >
                      <HStack spacing={4}>
                        <Center w={12} h={12} bg="white" borderRadius="xl" shadow="sm">
                          {allPossibleCategories.find(c => c.name === exp.category)?.emoji || '❓'}
                        </Center>
                        <VStack align="start" spacing={0}>
                          <Text fontWeight="bold" fontSize="sm">{exp.category}</Text>
                          <Text fontSize="10px" color="gray.400" fontWeight="bold" textTransform="uppercase">
                            {expDate.toLocaleDateString()} • {exp.created_by}
                          </Text>
                        </VStack>
                      </HStack>
                      <HStack spacing={3}>
                        <Text fontWeight="bold" fontFamily="mono" color="red.500">
                          -{exp.amount.toFixed(2)} €
                        </Text>
                        <IconButton
                          aria-label="Elimina"
                          icon={<span>🗑️</span>}
                          size="xs"
                          variant="ghost"
                          colorScheme="red"
                          onClick={() => deleteExpense(exp.id)}
                        />
                      </HStack>
                    </Flex>
                  </React.Fragment>
                );
              });
            })()}
          </VStack>
        )}
      </Box>
    </VStack>
  );
}

function TabBalance({ userName, toast }: { userName: string, toast: ReturnType<typeof useToast> }) {
  const [balance, setBalance] = useState({ matteo: 0, elena: 0 });
  const [settlements, setSettlements] = useState<Settlement[]>([]);
  const [loading, setLoading] = useState(true);
  const [settleAmount, setSettleAmount] = useState('0');

  const fetchData = async () => {
    setLoading(true);
    try {
      const { data: lastSettle } = await supabase.from('settlements').select('*').order('settled_at', { ascending: false }).limit(1);
      const lastDate = lastSettle?.[0]?.settled_at || '2000-01-01T00:00:00Z';
      
      const { data: allSettle } = await supabase.from('settlements').select('*').order('settled_at', { ascending: false }).limit(5);
      setSettlements(allSettle || []);

      const { data: expenses, error } = await supabase.from('expenses').select('*').gt('created_at', lastDate);
      if (error) throw error;

      if (expenses) {
        const matteoTotal = expenses.filter(e => e.created_by === 'Matteo').reduce((sum, e) => sum + e.amount, 0);
        const elenaTotal = expenses.filter(e => e.created_by === 'Elena').reduce((sum, e) => sum + e.amount, 0);
        setBalance({ matteo: matteoTotal, elena: elenaTotal });
        setSettleAmount(Math.abs((matteoTotal - elenaTotal) / 2).toFixed(2));
      }
    } catch (error: any) {
      console.error('Error fetching balance data:', error);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { fetchData(); }, []);

  const handleSettle = async () => {
    try {
      const amountToSettle = parseFloat(settleAmount);
      const { data, error } = await supabase
        .from('settlements')
        .insert({ amount: amountToSettle, settled_by: userName })
        .select();

      if (error) throw error;
      
      const newSettlementId = data?.[0]?.id;

      toast({
        duration: 5000,
        render: ({ onClose }) => (
          <Box m={3} color="white" p={4} bg="green.600" borderRadius="2xl" shadow="2xl">
            <VStack align="stretch" spacing={3}>
              <HStack justify="space-between">
                <HStack>
                  <Text fontSize="lg">🤝</Text>
                  <Text fontWeight="bold">Conto saldato!</Text>
                </HStack>
                <Button 
                  size="sm" 
                  variant="solid" 
                  colorScheme="whiteAlpha" 
                  onClick={async () => {
                    if (newSettlementId) {
                      await deleteSettlement(newSettlementId, true);
                    }
                    onClose();
                  }}
                >
                  Annulla
                </Button>
              </HStack>
            </VStack>
          </Box>
        ),
        position: 'top',
      });

      fetchData();
    } catch (error: any) {
      console.error('Error settling debt:', error);
      toast({ title: 'Errore durante il saldo', description: error.message, status: 'error' });
    }
  };

  const deleteSettlement = async (id: string, isUndo: boolean = false) => {
    try {
      const { error } = await supabase.from('settlements').delete().eq('id', id);
      if (error) throw error;
      fetchData();
      toast({ 
        title: isUndo ? 'Saldo annullato ↩️' : 'Conguaglio eliminato 🗑️', 
        status: 'info', 
        duration: 2000,
      });
    } catch (error: any) {
      console.error('Error deleting settlement:', error);
      toast({ title: 'Errore durante l\'eliminazione', description: error.message, status: 'error' });
    }
  };

  const diff = (balance.matteo - balance.elena) / 2;

  return (
    <VStack spacing={6} align="stretch" bg="white" p={8} borderRadius="3xl" shadow="sm" border="1px solid" borderColor="gray.100">
      <HStack spacing={3} mb={2}>
        <Text fontSize="xl">⚖️</Text>
        <Heading size="md" fontWeight="bold">Il Bilancio</Heading>
      </HStack>

      <VStack py={8} bg="gray.50" borderRadius="3xl" spacing={1}>
        <Text fontSize="sm" color="gray.500" fontWeight="medium">
          {diff > 0 ? 'Elena deve dare a Matteo' : diff < 0 ? 'Matteo deve dare a Elena' : 'Siete pari!'}
        </Text>
        <Text fontSize="5xl" fontFamily="mono" fontWeight="black" color="gray.900">
          € {Math.abs(diff).toFixed(2)}
        </Text>
      </VStack>

      <VStack spacing={4} align="stretch" my={2}>
        <Flex justify="space-between" align="center" fontSize="sm">
          <Text color="gray.500" fontWeight="medium">Pagato da Matteo</Text>
          <Text fontWeight="bold">€ {balance.matteo.toFixed(2)}</Text>
        </Flex>
        <Flex justify="space-between" align="center" fontSize="sm">
          <Text color="gray.500" fontWeight="medium">Pagato da Elena</Text>
          <Text fontWeight="bold" color="pink.600">€ {balance.elena.toFixed(2)}</Text>
        </Flex>
        <Divider />
        <Flex justify="space-between" align="center">
          <Text fontSize="xs" fontWeight="black" color="gray.400" textTransform="uppercase">Differenza Totale</Text>
          <Text fontSize="lg" fontWeight="bold">€ {Math.abs(balance.matteo - balance.elena).toFixed(2)}</Text>
        </Flex>
      </VStack>

      <Button 
        colorScheme="blackAlpha" 
        bg="black" 
        color="white"
        size="lg" 
        height="60px"
        borderRadius="2xl"
        onClick={handleSettle}
        isDisabled={diff === 0}
        _hover={{ bg: 'gray.800' }}
      >
        Salda Debito 🤝
      </Button>

      <Box pt={4}>
        <Text fontSize="xs" fontWeight="black" color="gray.400" textTransform="uppercase" mb={4}>Ultimi Conguagli</Text>
        <VStack spacing={3} opacity={0.7}>
          {settlements.map(s => (
            <Flex key={s.id} justify="space-between" align="center" fontSize="xs" fontWeight="bold">
              <HStack spacing={2}>
                <Text color="gray.500">{new Date(s.settled_at).toLocaleDateString('it-IT', { day: '2-digit', month: 'short', year: 'numeric' })}</Text>
                <IconButton
                  aria-label="Elimina conguaglio"
                  icon={<span>🗑️</span>}
                  size="xs"
                  variant="ghost"
                  colorScheme="red"
                  onClick={() => deleteSettlement(s.id)}
                />
              </HStack>
              <Text fontFamily="mono" color="green.600">€ {s.amount.toFixed(2)}</Text>
            </Flex>
          ))}
        </VStack>
      </Box>
    </VStack>
  );
}
