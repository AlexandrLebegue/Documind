'use client';

import { useState, useRef, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { createProcedure } from '@/lib/api';
import { PROCEDURE_TYPES } from '@/components/ProcedureTypeBadge';

type WizardStep = 'type' | 'name' | 'documents_choice' | 'image_upload' | 'manual_list' | 'remarks' | 'analyzing' | 'done';

interface Message {
  id: string;
  role: 'assistant' | 'user';
  content: string;
  component?: React.ReactNode;
}

export default function NewProcedurePage() {
  const router = useRouter();
  const [step, setStep] = useState<WizardStep>('type');
  const [messages, setMessages] = useState<Message[]>([
    {
      id: 'welcome',
      role: 'assistant',
      content: 'Bonjour ! Je vais vous aider à créer une nouvelle procédure. Commençons par choisir le type de procédure.',
    },
  ]);
  const [procedureType, setProcedureType] = useState('');
  const [procedureName, setProcedureName] = useState('');
  const [hasImage, setHasImage] = useState<boolean | null>(null);
  const [imageBase64, setImageBase64] = useState<string | null>(null);
  const [manualDocs, setManualDocs] = useState<string[]>([]);
  const [docInput, setDocInput] = useState('');
  const [remarks, setRemarks] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [createdId, setCreatedId] = useState<string | null>(null);
  const messagesEndRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages, step]);

  const addMessage = (role: 'assistant' | 'user', content: string) => {
    setMessages((prev) => [...prev, { id: `msg-${Date.now()}-${Math.random()}`, role, content }]);
  };

  // -- Step handlers --

  const handleSelectType = (type: string, label: string) => {
    setProcedureType(type);
    addMessage('user', label);
    setTimeout(() => {
      addMessage('assistant', `Parfait, une procédure de type « ${label} ». Quel nom souhaitez-vous donner à cette procédure ?`);
      setStep('name');
    }, 300);
  };

  const handleSetName = () => {
    const trimmed = procedureName.trim();
    if (!trimmed) return;
    addMessage('user', trimmed);
    setTimeout(() => {
      addMessage('assistant', `Procédure « ${trimmed} ». Avez-vous une image listant les documents nécessaires pour cette procédure ?`);
      setStep('documents_choice');
    }, 300);
  };

  const handleDocumentChoice = (choice: boolean) => {
    setHasImage(choice);
    addMessage('user', choice ? 'Oui, j\'ai une image' : 'Non, je vais les lister manuellement');
    setTimeout(() => {
      if (choice) {
        addMessage('assistant', 'Parfait ! Veuillez déposer ou sélectionner l\'image qui liste les documents nécessaires.');
        setStep('image_upload');
      } else {
        addMessage('assistant', 'Pas de problème. Ajoutez chaque document nécessaire un par un dans la liste ci-dessous. Cliquez sur « Terminer la liste » quand vous avez fini.');
        setStep('manual_list');
      }
    }, 300);
  };

  const handleImageUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    if (!file.type.startsWith('image/')) {
      setError('Veuillez sélectionner un fichier image (JPG, PNG, etc.)');
      return;
    }

    const reader = new FileReader();
    reader.onload = () => {
      const result = reader.result as string;
      // Extract base64 part (remove data:image/...;base64, prefix)
      const base64 = result.split(',')[1];
      setImageBase64(base64);
      addMessage('user', `Image chargée : ${file.name}`);
      setTimeout(() => {
        addMessage('assistant', 'Image reçue ! Souhaitez-vous ajouter des remarques supplémentaires concernant cette procédure ?');
        setStep('remarks');
      }, 300);
    };
    reader.readAsDataURL(file);
  };

  const handleAddDoc = () => {
    const trimmed = docInput.trim();
    if (!trimmed) return;
    setManualDocs((prev) => [...prev, trimmed]);
    setDocInput('');
  };

  const handleRemoveDoc = (index: number) => {
    setManualDocs((prev) => prev.filter((_, i) => i !== index));
  };

  const handleFinishList = () => {
    if (manualDocs.length === 0) {
      setError('Ajoutez au moins un document à la liste');
      return;
    }
    setError(null);
    addMessage('user', `Liste de ${manualDocs.length} document(s) :\n${manualDocs.map((d, i) => `${i + 1}. ${d}`).join('\n')}`);
    setTimeout(() => {
      addMessage('assistant', 'Liste notée ! Souhaitez-vous ajouter des remarques supplémentaires concernant cette procédure ?');
      setStep('remarks');
    }, 300);
  };

  const handleSubmitRemarks = () => {
    if (remarks.trim()) {
      addMessage('user', remarks.trim());
    } else {
      addMessage('user', 'Pas de remarques');
    }
    setTimeout(() => {
      addMessage('assistant', 'Merci ! Je lance l\'analyse par l\'IA pour créer votre procédure...');
      setStep('analyzing');
      submitProcedure();
    }, 300);
  };

  const handleSkipRemarks = () => {
    addMessage('user', 'Pas de remarques');
    setTimeout(() => {
      addMessage('assistant', 'Compris ! Je lance l\'analyse par l\'IA pour créer votre procédure...');
      setStep('analyzing');
      submitProcedure();
    }, 300);
  };

  const submitProcedure = async () => {
    try {
      setError(null);
      const result = await createProcedure({
        name: procedureName.trim() || undefined,
        procedure_type: procedureType,
        image_base64: imageBase64 || undefined,
        manual_documents: manualDocs.length > 0 ? manualDocs : undefined,
        remarks: remarks.trim() || undefined,
      });
      setCreatedId(result.id);
      addMessage('assistant', `✅ Procédure créée avec succès !\n\n**${result.name}**\n${result.description || ''}\n\n${result.required_documents.length} document(s) requis identifié(s).`);
      setStep('done');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Erreur lors de la création');
      addMessage('assistant', '❌ Une erreur est survenue lors de l\'analyse. Veuillez réessayer.');
      setStep('remarks');
    }
  };

  return (
    <div className="flex flex-col h-[calc(100vh-3.5rem)] md:h-screen">
      {/* Header */}
      <div className="flex-shrink-0 px-6 py-4 border-b border-beige-300 bg-white/50 backdrop-blur-sm">
        <div className="flex items-center gap-3">
          <button
            onClick={() => router.push('/procedures')}
            className="p-1.5 rounded-lg text-[#6b7280] hover:text-[#1a1a1a] hover:bg-beige-300/60 transition-colors"
          >
            <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <path d="M15 10H5" />
              <path d="M10 5L5 10L10 15" />
            </svg>
          </button>
          <div>
            <h1 className="text-lg font-bold text-[#1a1a1a]">Nouvelle procédure</h1>
            <p className="text-sm text-[#6b7280]">Assistant de création</p>
          </div>
        </div>
      </div>

      {/* Messages area */}
      <div className="flex-1 overflow-auto px-6 py-4 space-y-4">
        {messages.map((msg) => (
          <div
            key={msg.id}
            className={`flex ${msg.role === 'user' ? 'justify-end' : 'justify-start'}`}
          >
            <div className="flex items-end gap-2 max-w-[80%]">
              {msg.role === 'assistant' && (
                <div className="w-7 h-7 rounded-full bg-accent flex items-center justify-center text-xs font-bold text-white flex-shrink-0">
                  D
                </div>
              )}
              <div
                className={`px-4 py-3 rounded-2xl text-sm whitespace-pre-wrap ${
                  msg.role === 'user'
                    ? 'bg-accent text-white rounded-br-md'
                    : 'bg-white border border-beige-300/50 text-[#1a1a1a] rounded-bl-md shadow-sm'
                }`}
              >
                {msg.content}
              </div>
            </div>
          </div>
        ))}

        {/* Interactive step components */}
        {step === 'type' && (
          <div className="flex justify-start">
            <div className="flex items-end gap-2 max-w-[80%]">
              <div className="w-7 h-7 flex-shrink-0" />
              <div className="grid grid-cols-2 gap-2">
                {PROCEDURE_TYPES.map((t) => (
                  <button
                    key={t.value}
                    onClick={() => handleSelectType(t.value, t.label)}
                    className="px-4 py-3 bg-white border border-beige-300 rounded-xl text-sm font-medium text-[#1a1a1a] hover:bg-beige-50 hover:border-accent/30 transition-all text-left"
                  >
                    {t.label}
                  </button>
                ))}
              </div>
            </div>
          </div>
        )}

        {step === 'name' && (
          <div className="flex justify-start">
            <div className="flex items-end gap-2 max-w-[80%] w-full">
              <div className="w-7 h-7 flex-shrink-0" />
              <div className="bg-white border border-beige-300 rounded-xl p-4 space-y-3 flex-1">
                <div className="flex gap-2">
                  <input
                    type="text"
                    value={procedureName}
                    onChange={(e) => setProcedureName(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter') {
                        e.preventDefault();
                        handleSetName();
                      }
                    }}
                    placeholder="Ex: Inscription crèche, Ouverture compte..."
                    className="flex-1 px-3 py-2 bg-beige-50 border border-beige-300 rounded-lg text-sm text-[#1a1a1a] placeholder-[#6b7280] focus:outline-none focus:ring-2 focus:ring-accent/30"
                    autoFocus
                  />
                  <button
                    onClick={handleSetName}
                    disabled={!procedureName.trim()}
                    className="px-4 py-2 bg-accent text-white rounded-lg text-sm font-medium hover:bg-accent-hover transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    Valider
                  </button>
                </div>
              </div>
            </div>
          </div>
        )}

        {step === 'documents_choice' && (
          <div className="flex justify-start">
            <div className="flex items-end gap-2 max-w-[80%]">
              <div className="w-7 h-7 flex-shrink-0" />
              <div className="flex gap-2">
                <button
                  onClick={() => handleDocumentChoice(true)}
                  className="px-4 py-3 bg-white border border-beige-300 rounded-xl text-sm font-medium text-[#1a1a1a] hover:bg-beige-50 hover:border-accent/30 transition-all"
                >
                  📷 Oui, j&apos;ai une image
                </button>
                <button
                  onClick={() => handleDocumentChoice(false)}
                  className="px-4 py-3 bg-white border border-beige-300 rounded-xl text-sm font-medium text-[#1a1a1a] hover:bg-beige-50 hover:border-accent/30 transition-all"
                >
                  ✏️ Non, liste manuelle
                </button>
              </div>
            </div>
          </div>
        )}

        {step === 'image_upload' && (
          <div className="flex justify-start">
            <div className="flex items-end gap-2 max-w-[80%]">
              <div className="w-7 h-7 flex-shrink-0" />
              <div className="bg-white border border-beige-300 rounded-xl p-4 space-y-3">
                <label className="flex flex-col items-center justify-center w-full h-32 border-2 border-dashed border-beige-400 rounded-lg cursor-pointer hover:border-accent/50 transition-colors">
                  <svg width="32" height="32" viewBox="0 0 32 32" fill="none" stroke="#6b7280" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M4 20L11 13L18 20" />
                    <path d="M18 16L22 12L28 18" />
                    <rect x="4" y="4" width="24" height="24" rx="3" />
                    <circle cx="11" cy="11" r="2" />
                  </svg>
                  <p className="text-sm text-[#6b7280] mt-2">Cliquez ou glissez une image</p>
                  <input
                    type="file"
                    accept="image/*"
                    className="hidden"
                    onChange={handleImageUpload}
                  />
                </label>
              </div>
            </div>
          </div>
        )}

        {step === 'manual_list' && (
          <div className="flex justify-start">
            <div className="flex items-end gap-2 max-w-[85%] w-full">
              <div className="w-7 h-7 flex-shrink-0" />
              <div className="bg-white border border-beige-300 rounded-xl p-4 space-y-3 flex-1">
                {/* Document list */}
                {manualDocs.length > 0 && (
                  <ul className="space-y-2">
                    {manualDocs.map((doc, i) => (
                      <li key={i} className="flex items-center gap-2 text-sm">
                        <span className="w-5 h-5 bg-accent/10 text-accent rounded-full flex items-center justify-center text-xs font-medium flex-shrink-0">
                          {i + 1}
                        </span>
                        <span className="flex-1 text-[#1a1a1a]">{doc}</span>
                        <button
                          onClick={() => handleRemoveDoc(i)}
                          className="text-[#6b7280] hover:text-[#dc2626] transition-colors"
                        >
                          <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                            <path d="M3 3L11 11" />
                            <path d="M11 3L3 11" />
                          </svg>
                        </button>
                      </li>
                    ))}
                  </ul>
                )}

                {/* Add input */}
                <div className="flex gap-2">
                  <input
                    type="text"
                    value={docInput}
                    onChange={(e) => setDocInput(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter') {
                        e.preventDefault();
                        handleAddDoc();
                      }
                    }}
                    placeholder="Ex: Justificatif de domicile..."
                    className="flex-1 px-3 py-2 bg-beige-50 border border-beige-300 rounded-lg text-sm text-[#1a1a1a] placeholder-[#6b7280] focus:outline-none focus:ring-2 focus:ring-accent/30"
                  />
                  <button
                    onClick={handleAddDoc}
                    disabled={!docInput.trim()}
                    className="px-3 py-2 bg-accent text-white rounded-lg text-sm font-medium hover:bg-accent-hover transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    +
                  </button>
                </div>

                <button
                  onClick={handleFinishList}
                  disabled={manualDocs.length === 0}
                  className="w-full px-4 py-2 bg-accent text-white rounded-lg text-sm font-medium hover:bg-accent-hover transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  Terminer la liste ({manualDocs.length} document{manualDocs.length !== 1 ? 's' : ''})
                </button>
              </div>
            </div>
          </div>
        )}

        {step === 'remarks' && (
          <div className="flex justify-start">
            <div className="flex items-end gap-2 max-w-[80%] w-full">
              <div className="w-7 h-7 flex-shrink-0" />
              <div className="bg-white border border-beige-300 rounded-xl p-4 space-y-3 flex-1">
                <textarea
                  value={remarks}
                  onChange={(e) => setRemarks(e.target.value)}
                  placeholder="Remarques supplémentaires (optionnel)..."
                  className="w-full px-3 py-2 bg-beige-50 border border-beige-300 rounded-lg text-sm text-[#1a1a1a] placeholder-[#6b7280] focus:outline-none focus:ring-2 focus:ring-accent/30 resize-none"
                  rows={3}
                />
                <div className="flex gap-2">
                  <button
                    onClick={handleSkipRemarks}
                    className="flex-1 px-4 py-2 bg-white border border-beige-300 text-[#1a1a1a] rounded-lg text-sm font-medium hover:bg-beige-50 transition-colors"
                  >
                    Passer
                  </button>
                  <button
                    onClick={handleSubmitRemarks}
                    className="flex-1 px-4 py-2 bg-accent text-white rounded-lg text-sm font-medium hover:bg-accent-hover transition-colors"
                  >
                    Valider
                  </button>
                </div>
              </div>
            </div>
          </div>
        )}

        {step === 'analyzing' && (
          <div className="flex justify-start">
            <div className="flex items-end gap-2">
              <div className="w-7 h-7 rounded-full bg-accent flex items-center justify-center text-xs font-bold text-white flex-shrink-0">
                D
              </div>
              <div className="px-4 py-3 bg-white border border-beige-300/50 rounded-2xl rounded-bl-md shadow-sm">
                <div className="flex gap-1">
                  <span className="w-2 h-2 bg-[#6b7280] rounded-full animate-bounce" style={{ animationDelay: '0ms' }} />
                  <span className="w-2 h-2 bg-[#6b7280] rounded-full animate-bounce" style={{ animationDelay: '150ms' }} />
                  <span className="w-2 h-2 bg-[#6b7280] rounded-full animate-bounce" style={{ animationDelay: '300ms' }} />
                </div>
              </div>
            </div>
          </div>
        )}

        {step === 'done' && createdId && (
          <div className="flex justify-start">
            <div className="flex items-end gap-2 max-w-[80%]">
              <div className="w-7 h-7 flex-shrink-0" />
              <div className="flex gap-2">
                <button
                  onClick={() => router.push(`/procedures/view?id=${createdId}`)}
                  className="px-4 py-2.5 bg-accent text-white rounded-lg text-sm font-medium hover:bg-accent-hover transition-colors"
                >
                  Voir la procédure
                </button>
                <button
                  onClick={() => router.push('/procedures')}
                  className="px-4 py-2.5 bg-white border border-beige-300 text-[#1a1a1a] rounded-lg text-sm font-medium hover:bg-beige-50 transition-colors"
                >
                  Retour à la liste
                </button>
              </div>
            </div>
          </div>
        )}

        {/* Error */}
        {error && (
          <div className="flex justify-center">
            <div className="px-4 py-2 bg-red-50 border border-red-200 rounded-lg">
              <p className="text-xs text-[#dc2626]">{error}</p>
            </div>
          </div>
        )}

        <div ref={messagesEndRef} />
      </div>
    </div>
  );
}
